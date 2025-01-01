# typed: true
# frozen_string_literal: true

module Billing
  class ZeroOutLfsDatapacksJob < BillingJob
    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    retry_on StandardError

    queue_as :zero_out_lfs_datapacks

    locked_by timeout: ActiveJob::LockingJob::DEFAULT_LOCK_TIMEOUT, key: DEFAULT_LOCK_PROC

    sig { params(user_id: Integer).void }
    def perform(user_id)
      return unless GitHub.billing_enabled?

      log_fields = {
          "code.namespace" => "Billing::ZeroOutLfsDatapacksJob",
          "code.function" => "perform",
          "gh.user.id" => user_id,
        }

      user = User.includes(:customer, :asset_status).where(id: user_id).first
      if user.nil?
        GitHub.logger.info("User not found", log_fields)
        return
      else
        if user.delegate_billing_to_business?
          GitHub.logger.info(
            "Org is a part of enterprise - only resetting data packs and pending plan changes for data packs",
            log_fields.merge("gh.user.data_packs" => user.asset_status&.data_packs),
          )
          with_write do
            user.reset_data_packs
            clear_lfs_data_pack_pending_plan_changes(user, log_fields)
          end
        else
          customer = T.let(user.customer, T.nilable(Customer))
          if customer.nil?
            GitHub.logger.info("User has no customer", log_fields)

            with_write do
              customer = Billing::CreateCustomer.perform(user).customer
            end
            if customer.nil?
              GitHub.logger.info("Customer could not be created", log_fields)
              return
            end
          end

          with_write do
            billed_via_billing_platform = customer.billed_via_billing_platform?
            unless billed_via_billing_platform
              GitHub.logger.info("Onboarding customer to billing platform", log_fields)
              customer.onboard_to_all_billing_platform_products
            end

            GitHub.logger.info("Zeroing out LFS datapacks", log_fields)
            user.reset_data_packs

            if billed_via_billing_platform
              # if customer was already onboarded to billing platform, we need to call
              # update_subscription directly to set the contract effective date to the migration date
              # this would allow Zuora to calculate the credits back to customer accurately
              GitHub.logger.info("Calling update_subscription directly to remove data packs", log_fields)
              zuora_subscription = user.plan_subscription&.zuora_subscription
              if zuora_subscription
                zuora_subscription.active_rate_plans.each do |rate_plan|
                  rate_plan.rate_plan_charges.each do |rate_plan_charge|
                    if rate_plan_charge["name"].starts_with?("Git LFS Data Pack")
                      contract_effective_date = if customer.billing_platform_enabled_product&.migration_date.present?
                        customer.billing_platform_enabled_product&.migration_date.to_date.to_s
                      else
                        GitHub::Billing.today.to_s
                      end

                      GitHub.logger.info("Removing rate plan charge with id=#{rate_plan_charge["id"]} and date=#{contract_effective_date}", log_fields)
                      response = GitHub.zuorest_client.update_subscription(
                        zuora_subscription.number, { remove: [{
                                contractEffectiveDate: contract_effective_date,
                                ratePlanId: rate_plan["id"],
                        }] },
                        Billing::PlanSubscription::ZuoraSynchronizer::ZUORA_VERSION_HEADER
                      )
                      result = GitHub::Billing::Result.from_zuora(response)
                      if result.success?
                        # If this fails, the next subscription sync will attempt the update again
                        user.plan_subscription&.update_from_zuora_subscription
                        result
                      end
                    end
                  end
                end
              end
            else
              GitHub.logger.info("Scheduling Zuora subscription sync", log_fields)
              user.synchronize_general_purpose_subscription_later
            end

            clear_lfs_data_pack_pending_plan_changes(user, log_fields)
          end
        end
      end

      GitHub.logger.info("Done processing", log_fields)
      GitHub.dogstats.increment("billing.zero_out_lfs_datapacks_total")
    end

    private

    sig { params(user: User, log_fields: T::Hash[String, T.untyped]).void }
    def clear_lfs_data_pack_pending_plan_changes(user, log_fields)
      pending_plan_changes = user.pending_plan_changes.with_data_packs.incomplete

      if pending_plan_changes.any?
        GitHub.logger.info("Clearing Git LFS data pack pending plan changes for user", log_fields)
        pending_plan_changes.each do |pending_plan_change|
          pending_plan_change.update_attribute(:data_packs, nil)
          pending_plan_change.cancel unless pending_plan_change.has_changes?
        end
      end
    end
  end
end
