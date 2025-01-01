# typed: strict
# frozen_string_literal: true

require "configurable/microsoft_support_plan"

# This job is responsible for disentitling customers that are no longer entitled for
# Harmony support.
class ScheduledEnterpriseAgreementSupportPlanDisentitleJob < BatchedJob
  queue_as :support_plan_entitlement
  schedule interval: 30.days, condition: -> { !GitHub.enterprise? }
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
      fn: "ScheduledEnterpriseAgreementSupportPlanDisentitleJob.next_batch",
      offset_item_id: offset_item_id,
    })

    with_read do
      config_entries = Configuration::Entry
        .where(name: "microsoft_support_plan")
        .where(target_type: "business")
        .where(value: SupportEntitlement::SupportPlan::SUPPORTED_SUPPORT_PLANS)
        .where("configuration_entries.id > ?", offset_item_id)
        .order(id: :asc)
        .limit(BATCH_SIZE)
    end
  end

  sig { override.params(configuration_entries: ActiveRecord::Relation, args: T.untyped, options: T.untyped).void }
  def process_batch(configuration_entries, *args, **options)
    client = SupportEntitlement::Braavos::Client

    businesses_with_config_entries(configuration_entries).each do |business_with_config_entry|
      begin
        business = business_with_config_entry[:business]
        config_entry = business_with_config_entry[:config_entry]

        next if business.nil? || business.metered_plan? || business.sales_managed_trial?

        response = client.check_entitlements_by_ea(id: business.id)

        if response.nil?
          unset_microsoft_support_plan(business, config_entry.value, nil)

          next
        end

        eans = response[:eans].to_a
        salesforce_account_id = response[:salesforce_account_id]
        agreements = response[:agreements].to_a

        next unless agreements.empty? || has_no_valid_support_agreement?(agreements) || get_active_agreement_ids(business, eans).empty?

        unset_microsoft_support_plan(business, config_entry.value, salesforce_account_id)
      rescue SupportEntitlement::Braavos::Client::ApiError => e
        GitHub.dogstats.increment("scheduled_enterprise_agreement_support_plan_disentitle_job.error", tags: ["error:#{e.class}"])
        GitHub.logger.error({
          message: "Error fetching agreements for enterprise",
          fn: "ScheduledEnterpriseAgreementSupportPlanDisentitleJob.process_batch",
          exception: e,
          business_id: business.id,
        })
      end
    end
  end

  private

  sig { params(agreements: T.untyped).returns(T::Boolean) }
  def has_no_valid_support_agreement?(agreements)
    tpids_with_support_plans = agreements.map do |agreement|
      service_offering_ids = agreement[:packages]&.map { |package| package[:serviceOfferingId] }&.uniq || []

      service_offering_ids.filter_map do |service_offering_id|
        SupportEntitlement::SupportPlan::SUPPORT_PLAN_MAPPING[service_offering_id]
      end
    end.flatten.empty?
  end

  sig { params(config_entries: ActiveRecord::Relation).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def businesses_with_config_entries(config_entries)
    business_ids = config_entries.map(&:target_id)

    businesses = Business.where(id: business_ids).each_with_object({}) do |business, obj|
      obj[business.id] = business
    end

    config_entries.each_with_object({}) do |config_entry, obj|
      business_id = config_entry.target_id
      obj[business_id] = { config_entry: config_entry, business: businesses[business_id] }
    end.values
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

  sig { params(business: Business, existing_plan: String, salesforce_account_id: T.nilable(String)).void }
  def unset_microsoft_support_plan(business, existing_plan, salesforce_account_id)
    with_write { business.update(microsoft_support_plan: nil) }

    GitHub.dogstats.increment("scheduled_enterprise_agreement_support_plan_disentitle_job.unset_microsoft_support_plan")

    GitHub.logger.info({
      message: "Unset Microsoft Support Plan for Enterprise",
      fn: "ScheduledEnterpriseAgreementSupportPlanDisentitleJob.unset_microsoft_support_plan",
      business_id: business.id,
      previous_support_plan: existing_plan
    })

    GlobalInstrumenter.instrument("microsoft_enterprise_agreement.support_disentitlement", {
      business: business,
      previous_support_plan: existing_plan,
      salesforce_account_id: salesforce_account_id
    })
  end
end
