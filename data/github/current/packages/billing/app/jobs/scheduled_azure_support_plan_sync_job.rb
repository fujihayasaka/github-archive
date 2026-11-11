# typed: strict
# frozen_string_literal: true

require "configurable/microsoft_support_plan"

# This job is responsible for setting the appropriate support plan on an Enterprise Account's that have a linked
# Azure Subscription. Uses the Braavos API to check the entitlement of the Azure Subscription.
class ScheduledAzureSupportPlanSyncJob < BatchedJob
  queue_as :support_plan_entitlement
  schedule interval: 1.day, condition: -> { !GitHub.enterprise? }
  retry_on_dirty_exit
  retry_on_recoverable_exceptions do |_job, error|
    GitHub.dogstats.increment(
      "scheduled_azure_support_plan_sync_job.error",
      tags: ["error:#{error.class}"],
    )
    raise error
  end

  BATCH_SIZE = 50

  # Grace period after an agreement's endDate before a business would be
  # considered for disentitlement. When the harmony_azure_disentitle_expired_packages
  # feature flag is enabled we disentitle; otherwise we only log.
  DISENTITLEMENT_GRACE_PERIOD = T.let(30.days, ActiveSupport::Duration)

  ACTIVE_CONTRACT = "Active Contract"
  PREMIER = "Premier"
  PROFESSIONAL = "Professional"
  PREMIUM_PREMIER = Configurable::MicrosoftSupportPlan::PREMIER
  PREMIUM_UNIFIED = Configurable::MicrosoftSupportPlan::PREMIUM_UNIFIED
  PREMIUM_PREMIER_ASFP = Configurable::MicrosoftSupportPlan::PREMIUM_PREMIER_ASFP
  PREMIUM_PREMIER_PSFP = Configurable::MicrosoftSupportPlan::PREMIUM_PREMIER_PSFP
  CLASSIC = "CLASSIC"
  UNIFIED = "UNIFIED"
  # SERVICE_OFFERING_MAPPING is a mapping of the service offering IDs to the support plan types.
  # The keys should be listed in order of support plan precedence.
  SERVICE_OFFERING_MAPPING = T.let({
    PREMIUM_UNIFIED => Configurable::MicrosoftSupportPlan::PREMIUM_UNIFIED_MSFT_SERVICE_IDS,
    PREMIUM_PREMIER => Configurable::MicrosoftSupportPlan::PREMIUM_PREMIER_MSFT_SERVICE_IDS,
    PREMIUM_PREMIER_PSFP => Configurable::MicrosoftSupportPlan::PREMIUM_PREMIER_PSFP_SERVICE_IDS,
    PREMIUM_PREMIER_ASFP => Configurable::MicrosoftSupportPlan::PREMIUM_PREMIER_ASFP_SERVICE_IDS,
  }.freeze, T::Hash[String, T::Array[Integer]])

  sig { override.params(offset_item_id: Integer, options: T.untyped).returns(ActiveRecord::Relation) }
  def next_batch(offset_item_id: 0, **options)
    GitHub.logger.info({
      message: "Fetching the next batch of enterprises",
      fn: "ScheduledAzureSupportPlanSyncJob.next_batch",
      offset_item_id: offset_item_id,
    })

    Customer.includes(:business)
      .where.not(azure_subscription_id: nil)
      .where("id > ?", offset_item_id)
      .where(metered_ghe: true)
      .order(id: :asc)
      .limit(BATCH_SIZE)
  end

  sig { override.params(customers: ActiveRecord::Relation, args: T.untyped, options: T.untyped).void }
  def process_batch(customers, *args, **options)
    client = SupportEntitlement::Braavos::Client

    customers.each do |customer|
      begin
        business = customer.business
        next unless business

        response = client.check_entitlement(customer.azure_subscription_id)

        # https://eng.ms/docs/cloud-ai-platform/commerce-ecosystems/customer-experience/dps-delivery-enablement/agreement-management/partner-docs/consumers/datadictionary#agreement---get-by-id
        #
        # type: is one of the following: "Professional", "Premier"
        # condition: is one of the following: "Active Contract", "Closed Contract", "Quote"
        # isRevoked: is this Closed Contract = true
        type = response[:type]
        condition = response[:condition]
        is_revoked = response[:isRevoked]
        # packages: is an array of packages. We want to look at each package and set the support plan based on the serviceOfferingId.
        # If at least one package is UNIFIED, we should set the support plan to premium_unified.
        # If there are no UNIFIED packages, but at least one CLASSIC package, we should set the support plan to premium_premier.
        service_offering_ids = response[:packages]&.map { |package| package[:serviceOfferingId] }&.uniq
        support_plan = SERVICE_OFFERING_MAPPING.keys.find do |key|
          SERVICE_OFFERING_MAPPING[key]&.any? { |code| service_offering_ids&.include?(code) }
        end
        not_found = response[:not_found]

        # If the contract is revoked or not found, we should clear the microsoft support plan if it exists.
        if is_revoked || not_found
          update_microsoft_support_plan(business, nil) if business.microsoft_support_plan.present?
        elsif condition == ACTIVE_CONTRACT
          case type
          when PREMIER
            if support_plan
              # The endDate on the eligible packages tells us when the support
              # agreement actually ends. We allow a grace period past that date
              # before considering the business for disentitlement. When the
              # feature flag is enabled we clear the support plan (or skip
              # entitling a brand-new business) and move on. Otherwise we only
              # log so we can monitor the impact before changing behavior.
              if all_eligible_packages_expired?(response, business: business)
                if FeatureFlag.vexi.enabled?(:harmony_azure_disentitle_expired_packages, business, default: false)
                  update_microsoft_support_plan(business, nil) if business.microsoft_support_plan.present?
                  next
                # We still want to ensure that they have an existing plan before logging this detail
                elsif business.microsoft_support_plan.present?
                  latest_end_date = latest_eligible_package_end_date(response)
                  earliest_start_date = earliest_eligible_package_start_date(response)
                  log_would_be_disentitled_due_to_expired_agreement(
                    business,
                    earliest_start_date: earliest_start_date,
                    latest_end_date: latest_end_date,
                  )
                end
              end

              update_microsoft_support_plan(business, support_plan) unless business.microsoft_support_plan == support_plan
            else
              GitHub.dogstats.increment("scheduled_azure_support_plan_sync_job.unknown_microsoft_support_plan_service_offering_id")
              GitHub.logger.error({
                message: "Braavos returned an unknown Microsoft Support plan service offering id",
                fn: "ScheduledAzureSupportPlanSyncJob.process_batch",
                business_id: customer.business.id,
                service_offering_ids: service_offering_ids,
              })
            end
          when PROFESSIONAL
            nil
          else
            GitHub.dogstats.increment("scheduled_azure_support_plan_sync_job.unknown_microsoft_support_plan_type", tags: ["plan_type:#{type}"])
            GitHub.logger.error({
              message: "Braavos returned an unknown Microsoft Support Plan type",
              fn: "ScheduledAzureSupportPlanSyncJob.process_batch",
              business_id: customer.business.id,
              type: type,
            })
          end
        end
      rescue Configurable::MicrosoftSupportPlan::InvalidMicrosoftSupportPlan, SupportEntitlement::Braavos::Client::ApiError => e
        GitHub.dogstats.increment("scheduled_azure_support_plan_sync_job.error", tags: ["error:#{e.class}"])
        GitHub.logger.error({
          message: "Error setting Microsoft Support Plan for Enterprise",
          fn: "ScheduledAzureSupportPlanSyncJob.process_batch",
          exception: e,
          business_id: customer.business.id,
        })
      end
    end
  end

  private

  # Returns true when every package in the response that maps to a known
  # support plan has an endDate older than the configured grace period.
  # Returns false when there are no eligible packages so that we don't
  # treat "no packages" as "expired". Packages with a missing or
  # unparseable endDate are treated as not expired so that we don't
  # disentitle a customer based on bad data from the upstream API; a
  # WARN log is emitted so we can be alerted to these cases.
  sig { params(response: T::Hash[Symbol, T.untyped], business: Business).returns(T::Boolean) }
  def all_eligible_packages_expired?(response, business:)
    eligible_packages = (response[:packages] || []).select do |package|
      SERVICE_OFFERING_MAPPING.values.flatten.include?(package[:serviceOfferingId])
    end

    return false if eligible_packages.empty?

    cutoff = Time.current - DISENTITLEMENT_GRACE_PERIOD

    eligible_packages.all? do |package|
      end_date = package[:endDate]

      if end_date.blank?
        log_unparseable_end_date(package, business: business, reason: "missing")
        next false
      end

      begin
        DateTime.parse(end_date.to_s) < cutoff
      rescue Date::Error
        log_unparseable_end_date(package, business: business, reason: "unparseable")
        false
      end
    end
  end

  sig { params(package: T::Hash[Symbol, T.untyped], business: Business, reason: String).void }
  def log_unparseable_end_date(package, business:, reason:)
    GitHub.dogstats.increment(
      "scheduled_azure_support_plan_sync_job.invalid_package_end_date",
      tags: ["reason:#{reason}"],
    )
    GitHub.logger.warn({
      message: "Braavos package endDate is #{reason}; treating package as not expired",
      fn: "ScheduledAzureSupportPlanSyncJob.all_eligible_packages_expired?",
      business_id: business.id,
      business_slug: business.slug,
      service_offering_id: package[:serviceOfferingId],
      unique_id: package[:uniqueID],
      end_date: package[:endDate],
    })
  end

  sig { params(business: Business, earliest_start_date: T.nilable(String), latest_end_date: T.nilable(String)).void }
  def log_would_be_disentitled_due_to_expired_agreement(business, earliest_start_date:, latest_end_date:)
    GitHub.logger.info({
      message: "Business would be disentitled due to expired enterprise agreement",
      fn: "ScheduledAzureSupportPlanSyncJob.process_batch",
      business_id: business.id,
      business_slug: business.slug,
      salesforce_id: business.salesforce_account&.salesforce_id,
      earliest_package_start_date: earliest_start_date,
      latest_package_end_date: latest_end_date,
    })
  end

  # Returns the earliest startDate (as a YYYY-MM-DD string) among the packages
  # in the response that map to a known support plan. Packages with a missing
  # or unparseable startDate are ignored. Returns nil when no eligible package
  # has a usable startDate.
  sig { params(response: T::Hash[Symbol, T.untyped]).returns(T.nilable(String)) }
  def earliest_eligible_package_start_date(response)
    start_dates = (response[:packages] || []).filter_map do |package|
      next unless SERVICE_OFFERING_MAPPING.values.flatten.include?(package[:serviceOfferingId])

      start_date = package[:startDate]
      next if start_date.blank?

      begin
        DateTime.parse(start_date.to_s)
      rescue Date::Error
        nil
      end
    end

    start_dates.min&.strftime("%Y-%m-%d")
  end

  # Returns the latest endDate (as a YYYY-MM-DD string) among the packages in
  # the response that map to a known support plan. Packages with a missing
  # or unparseable endDate are ignored. Returns nil when no eligible package
  # has a usable endDate.
  sig { params(response: T::Hash[Symbol, T.untyped]).returns(T.nilable(String)) }
  def latest_eligible_package_end_date(response)
    end_dates = (response[:packages] || []).filter_map do |package|
      next unless SERVICE_OFFERING_MAPPING.values.flatten.include?(package[:serviceOfferingId])

      end_date = package[:endDate]
      next if end_date.blank?

      begin
        DateTime.parse(end_date.to_s)
      rescue Date::Error
        nil
      end
    end

    end_dates.max&.strftime("%Y-%m-%d")
  end

  sig { params(business: Business, plan: T.nilable(String)).void }
  def update_microsoft_support_plan(business, plan)
    with_write { business.update(microsoft_support_plan: plan) }
    GitHub.dogstats.increment("scheduled_azure_support_plan_sync_job.microsoft_support_plan_updated", tags: ["plan:#{plan ? plan : 'standard'}"])
    GitHub.logger.info({
      message: "Updated Microsoft Support Plan for Enterprise",
      fn: "ScheduledAzureSupportPlanSyncJob.update_microsoft_support_plan",
      business_id: business.id,
      plan: plan,
    })
  end
end
