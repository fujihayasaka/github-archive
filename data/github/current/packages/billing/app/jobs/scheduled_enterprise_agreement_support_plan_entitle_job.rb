# typed: strict
# frozen_string_literal: true

require "configurable/microsoft_support_plan"

# This job is responsible for setting the Microsoft support plan on Enterprise accounts that
# have Harmony support through their Enterprise Agreement.
class ScheduledEnterpriseAgreementSupportPlanEntitleJob < BatchedJob
  queue_as :support_plan_entitlement
  schedule interval: 1.day, condition: -> { !GitHub.enterprise? }
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  BATCH_SIZE = 50

  sig { params(args: T.untyped, initial_start: Time, offset_item_id: Integer, progress: Integer, options: T.untyped).void }
  def perform(*args, initial_start: Time.now.utc, offset_item_id: 0, progress: 0, **options)
    super
  end

  sig { override.params(offset_item_id: Integer, options: T.untyped).returns(ActiveRecord::Relation) }
  def next_batch(offset_item_id: 0, **options)
    GitHub.logger.info({
      message: "Fetching the next batch of enterprises",
      fn: "ScheduledEnterpriseAgreementSupportPlanEntitleJob.next_batch",
      offset_item_id: offset_item_id,
    })

    # Once the salesforce table has been added into dotcom
    # we should update this query to only include customers with
    # TPID's and EAN's.
    with_read do
      Business.volume_ghe
        .not_staff_owned
        .where(customers: { billing_type: "invoice" })
        .where("businesses.id > ?", offset_item_id)
        .order(id: :asc)
        .limit(BATCH_SIZE)
    end
  end

  sig { override.params(businesses: ActiveRecord::Relation, args: T.untyped, options: T.untyped).void }
  def process_batch(businesses, *args, **options)
    client = SupportEntitlement::Braavos::Client
    msft_support_plan_mapping = microsoft_support_plans_for_batch_ids(ids: businesses.map(&:id))

    businesses.each do |business|
      begin
        response = client.check_entitlements_by_ea(id: business.id)

        next if response.nil?

        eans = response[:eans].to_a
        salesforce_account_id = response[:salesforce_account_id]
        agreements = response[:agreements].to_a

        next if agreements.empty?

        top_eligible_package = top_eligible_package(agreements: agreements, business: business)

        next if top_eligible_package.nil?

        active_agreements_ids = get_active_agreement_ids(business, eans)

        next if active_agreements_ids.empty?

        new_support_plan = top_eligible_package[:support_plan]
        existing_support_plan = msft_support_plan_mapping[business.id]

        next if new_support_plan.nil? || unsupported_plan?(existing_support_plan)

        GlobalInstrumenter.instrument("microsoft_enterprise_agreement.support_entitlement", {
          business: business,
          support_plan: new_support_plan,
          previous_support_plan: existing_support_plan,
          tpid: top_eligible_package[:tpid],
          eans: active_agreements_ids,
          salesforce_account_id: salesforce_account_id,
          start_date: protobuf_timestamp(top_eligible_package[:start_date]),
          end_date: protobuf_timestamp(top_eligible_package[:end_date]),
          customer_name: top_eligible_package[:customer_name],
          latest_agreement_id: top_eligible_package[:latest_agreement_id],
          service_offering_id: top_eligible_package[:service_offering_id].to_s,
          agreement_region_id: top_eligible_package[:region_id].to_s
        })

        update_microsoft_support_plan(business, new_support_plan, existing_support_plan) if new_support_plan != existing_support_plan
      rescue SupportEntitlement::Braavos::Client::ApiError => e
        GitHub.dogstats.increment("scheduled_enterprise_agreement_support_plan_entitle_job.error", tags: ["error:#{e.class}"])
        GitHub.logger.error({
          message: "Error fetching agreements for enterprise",
          fn: "ScheduledEnterpriseAgreementSupportPlanEntitleJob.process_batch",
          exception: e,
          business_id: business.id,
        })
      end
    end
  end

  private

  # This check is used to ensure that we don't accidentally entitle somebody for Premium Unified
  # when they have an even greater plan like GitHub Engineering Direct (Microsoft) that this job
  # doesn't currently support entitlement for.
  sig { params(plan: T.nilable(String)).returns(T::Boolean) }
  def unsupported_plan?(plan)
    !plan.nil? && !SupportEntitlement::SupportPlan::SUPPORTED_SUPPORT_PLANS.include?(plan)
  end

  sig { params(business: Business, eans: T::Array[String]).returns(T::Array[String]) }
  def get_active_agreement_ids(business, eans)
    # This is not scoped to a particular business as there is a restriction in Dotcom where one enterprise agreement
    # cannot belong to multiple enterprise accounts. From a harmony entitlement point of view
    # and a salesforce point of view a single enterprise agreements can belong to multiple enterprise accounts.
    # Here we use Salesforce as the source of truth for agreement associations with an EA and we use Dotcom
    # to verify that the enterprise agreement exists and is active.
    agreements_from_eans = Licensing::EnterpriseAgreement.where(agreement_id: eans, status: :active)

    return agreements_from_eans.map(&:agreement_id) unless agreements_from_eans.empty?

    # Fall back to associated enterprise agreements if we can't find any from the eans.
    agreements_from_relation = business.enterprise_agreements.where(status: :active)
    agreements_from_relation.map(&:agreement_id)
  end

  sig { params(ids: T::Array[Integer]).returns(T::Hash[T.untyped, T.untyped]) }
  def microsoft_support_plans_for_batch_ids(ids:)
    Configuration::Entry
      .where(name: "microsoft_support_plan", target_type: "Business", target_id: ids)
      .each_with_object({}) do |config_entry, obj|
        obj[config_entry.target_id] = config_entry.value
      end
  end

  # Iterates through all agreements and gets the top eligible package based on all agreements.
  # Here we also convert the package into a more Ruby friendly structure and only include
  # the mapped support plan, start date, end date and associated TPID.
  sig { params(agreements: T::Array[T::Hash[Symbol, T.untyped]], business: Business).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def top_eligible_package(agreements:, business:)
    packages = agreements.flat_map do |agreement|
      tpid = agreement[:tpid]
      unique_packages = agreement[:packages]&.uniq || []

      unique_packages.filter_map do |package|
        support_plan = SupportEntitlement::SupportPlan::SUPPORT_PLAN_MAPPING[package[:serviceOfferingId]]
        next unless support_plan

        {
          support_plan: support_plan,
          start_date: package[:startDate],
          end_date: package[:endDate],
          tpid: tpid,
          customer_name: agreement[:customerName],
          latest_agreement_id: package[:latestAgreementId],
          service_offering_id: package[:serviceOfferingId],
          region_id: package[:regionId],
        }
      end
    end

    package_dates = earliest_and_latest_package_dates_by_tpid(packages, business)

    top_package = packages.max_by do |package|
      [
        # Primary: Higher support plan is the first preference
        SupportEntitlement::SupportPlan::SUPPORT_PLAN_PRECEDENCE.fetch(package[:support_plan], 0),
        # Secondary: Tie-breaker using agreement ID (lowest wins)
        -package[:latest_agreement_id].to_i
      ]
    end

    if top_package.present?
      package_dates_for_tpid = package_dates[top_package[:tpid]]

      # Use the earliest start and latest end date out of all active support contracts
      # for billing purposes for the start and end date. This gives us the total
      # time window that the customer has had either unified or premier support.
      if package_dates_for_tpid.present?
        top_package[:start_date] = package_dates_for_tpid[:start_date]
        top_package[:end_date] = package_dates_for_tpid[:end_date]
      end
    end

    top_package
  end

  sig { params(packages: T::Array[T::Hash[Symbol, T.untyped]], business: Business).returns(T::Hash[String, T::Hash[Symbol, DateTime]]) }
  def earliest_and_latest_package_dates_by_tpid(packages, business)
    dates_by_tpid = {}

    packages.each do |package|
      tpid = package[:tpid]
      start_date = package[:start_date]
      end_date = package[:end_date]

      begin
        start_date = DateTime.parse(start_date.to_s)
        end_date = DateTime.parse(end_date.to_s)
      rescue Date::Error
        GitHub.logger.error({
          message: "invalid date passed",
          fn: "MicrosoftEnterpriseAgreement.earliest_and_latest_package_dates_by_tpid",
          business_id: business.id,
        })

        next
      end

      if dates_by_tpid.has_key?(tpid)
        dates_by_tpid[tpid][:start_date] = [dates_by_tpid[tpid][:start_date], start_date].min
        dates_by_tpid[tpid][:end_date] = [dates_by_tpid[tpid][:end_date], end_date].max
      else
        dates_by_tpid[tpid] = { start_date: start_date, end_date: end_date }
      end
    end

    dates_by_tpid
  end

  sig { params(business: Business, new_plan: String, existing_plan: T.nilable(String)).void }
  def update_microsoft_support_plan(business, new_plan, existing_plan)
    with_write { business.update(microsoft_support_plan: new_plan) }
    GitHub.dogstats.increment("scheduled_enterprise_agreement_support_plan_entitle_job.microsoft_support_plan_updated", tags: ["plan:#{new_plan}"])
    GitHub.logger.info({
      message: "Updated Microsoft Support Plan for Enterprise",
      fn: "ScheduledEnterpriseAgreementSupportPlanEntitleJob.update_microsoft_support_plan",
      business_id: business.id,
      support_plan: new_plan,
      previous_support_plan: existing_plan
    })
  end

  sig { params(datetime: T.untyped).returns(T.nilable(Google::Protobuf::Timestamp)) }
  def protobuf_timestamp(datetime)
    return nil unless datetime.is_a?(DateTime)

    Google::Protobuf::Timestamp.new(seconds: datetime.to_i)
  end
end
