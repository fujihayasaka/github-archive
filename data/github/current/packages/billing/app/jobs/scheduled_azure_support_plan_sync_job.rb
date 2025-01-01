# typed: strict
# frozen_string_literal: true

# This job is responsible for setting the appropriate support plan on an Enterprise Account's that have a linked
# Azure Subscription. Uses the Braavos API to check the entitlement of the Azure Subscription.
class ScheduledAzureSupportPlanSyncJob < BatchedJob
  extend T::Sig

  queue_as :support_plan_entitlement
  schedule interval: 1.day, condition: -> { !GitHub.enterprise? }
  retry_on_dirty_exit
  retry_on_recoverable_exceptions
  BATCH_SIZE = 50


  ACTIVE_CONTRACT = "Active Contract"
  PREMIER = "Premier"
  PROFESSIONAL = "Professional"
  PREMIUM_UNIFIED = "premium_unified"
  PREMIUM_PREMIER = "premium_premier"
  GHED = "premium_plus_engineering_direct"
  PREMIUM_PREMIER_ASFP = "premium_premier_asfp"
  PREMIUM_PREMIER_PSFP = "premium_premier_psfp"
  CLASSIC = "CLASSIC"
  UNIFIED = "UNIFIED"
  # SERVICE_OFFERING_MAPPING is a mapping of the service offering IDs to the support plan types.
  # The keys should be listed in order of support plan precedence.
  SERVICE_OFFERING_MAPPING = T.let({
    GHED => [1265, 1266],
    PREMIUM_UNIFIED => [1133, 1134, 1221, 1267, 1271, 1272, 1273, 1274, 1275, 1276, 1283, 1432, 1539, 1579],
    PREMIUM_PREMIER => [21, 208, 315, 327, 329, 355, 368, 372, 373, 517, 522, 602, 603, 688, 700, 701, 803, 842, 1001, 1020, 1142, 1154, 1201, 1279],
    PREMIUM_PREMIER_PSFP => [828, 832, 836, 1044, 1047, 1048, 1053, 1054],
    PREMIUM_PREMIER_ASFP => [1158, 1204, 1205],
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
        is_revoked = response[:is_revoked]
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

  sig { params(business: Business, plan: T.nilable(String)).void }
  def update_microsoft_support_plan(business, plan)
    if GitHub.flipper[:harmony_entitlement_api].enabled?
      with_write { business.update(microsoft_support_plan: plan) }
      GitHub.dogstats.increment("scheduled_azure_support_plan_sync_job.microsoft_support_plan_updated", tags: ["plan:#{plan ? plan : 'standard'}"])
      GitHub.logger.info({
        message: "Updated Microsoft Support Plan for Enterprise",
        fn: "ScheduledAzureSupportPlanSyncJob.update_microsoft_support_plan",
        business_id: business.id,
        plan: plan,
      })
    else
      GitHub.logger.info({
        message: "Skipping update of Microsoft Support Plan because feature flag is disabled",
        fn: "ScheduledAzureSupportPlanSyncJob.update_microsoft_support_plan",
        business_id: business.id,
        plan: plan,
      })
    end
  end
end
