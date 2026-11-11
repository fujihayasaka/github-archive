# typed: strict
# frozen_string_literal: true

# AdvancedSecurityLockMeteredUsageScheduledJob iterates through Businesses and Orgs that are using GHAS metered billing:
# 1. checks their billing status via CanProceedWithUsage
# 2. locks additional usage of metered GHAS SKUs when the check fails
module AdvancedSecurity
  class LockMeteredUsageScheduledJob < ApplicationJob
    queue_as :advanced_security_metered_lock

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    sig { params(actor: T::any(Business, Organization)).returns(T::Boolean) }
    def self.writes_enabled?(actor)
      actor.feature_flag_enabled?("ghas_cpwu_integration", default: false)
    end

    sig { params(actor: T::any(Business, Organization)).returns(T::Boolean) }
    def self.disabled_for_actor?(actor)
      actor.feature_flag_enabled?("disable_ghas_cpwu_lock", default: false)
    end

    class BusinessLockJob < ApplicationJob
      queue_as :advanced_security_metered_lock

      retry_on_dirty_exit
      retry_on_recoverable_exceptions
      retry_on AdvancedSecurity::ServiceError

      locked_by timeout: 1.hour, key: ->(job) {
        job.arguments[0]
      }

      sig { params(business_id: Integer).void }
      def perform(business_id:)
        GitHub.logger.with_named_tags(
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.business.id": business_id,
        ) do
          GitHub.logger.info("begin advanced security canProceedWithUsage check for business")

          business = Business.find_by(id: business_id)
          return GitHub.logger.error("business can't be nil") if business.nil?
          return GitHub.logger.error("business must be the advanced_security_billable_entity") unless business.advanced_security_billable_entity?
          return GitHub.logger.error("business must be using metered billing") unless business.advanced_security_metered_for_entity?
          return GitHub.logger.error("business must have a customer") if business.customer.nil?
          return GitHub.logger.info("skipping business on copilot standalone plan") if business.seats_plan_basic?
          return GitHub.logger.info("skipping business on sales managed trial") if business.sales_managed_trial?
          return GitHub.logger.info("skipping business excluded by feature flag") if LockMeteredUsageScheduledJob.disabled_for_actor?(business)

          writes_enabled = LockMeteredUsageScheduledJob.writes_enabled?(business)
          service = AdvancedSecurity::MeteredUsageService.new
          customer = T::must(business.customer)
          customer_id = customer.id

          skus = T.let([], T::Array[GitHub::Turboghas::SKU])
          if business.advanced_security_products_bundled?
            skus << GitHub::Turboghas::SKU::Bundled
          else
            skus << GitHub::Turboghas::SKU::CodeSecurity if business.code_security_purchased?
            skus << GitHub::Turboghas::SKU::SecretSecurity if business.secret_protection_purchased?
          end
          skus.each do |sku|
            # If the SKU is already locked, skip the whole thing to avoid unnecessary API calls and duplicate metrics and notifications
            next if service.sku_locked_for_entity?(business, sku)

            can_proceed, reason = service.can_proceed_with_usage?(customer_id, sku)
            next if can_proceed

            log_tags = { "gh.darkship": !writes_enabled, "gh.business.name": business.name, "gh.sku": sku.to_param }
            GitHub.logger.info("business failed canProceedWithUsage for metered GHAS SKU", { "gh.reason": reason }.merge(log_tags))
            GitHub.dogstats.increment("advanced_security.metered_usage.locked",
              tags: ["sku:#{sku.to_param}", "reason:#{reason}", "darkship:#{!writes_enabled}", "entity_type:business"])

            # Darkship metrics for warehouse
            if !writes_enabled
              message = { business_id: business.id, sku: sku, reason: reason }
              GitHub.instrument("advanced_security_billing.darkship.ghas_metered_usage_locked", message)
            end

            next unless writes_enabled

            with_write { service.lock_sku_for_entity(business, sku, reason) }
            GitHub.logger.info("locked metered GHAS SKU for business", log_tags)
          end
        end
      end
    end

    class UserLockJob < ApplicationJob
      queue_as :advanced_security_metered_lock

      retry_on_dirty_exit
      retry_on_recoverable_exceptions
      retry_on AdvancedSecurity::ServiceError

      locked_by timeout: 1.hour, key: ->(job) {
        job.arguments[0]
      }

      sig { params(user_id: Integer).void }
      def perform(user_id:)
        GitHub.logger.with_named_tags(
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.user.id": user_id,
        ) do
          GitHub.logger.info("begin advanced security canProceedWithUsage check for organization")

          user = User.find_by(id: user_id)
          return GitHub.logger.error("user can't be nil") if user.nil?
          return GitHub.logger.error("user must be an organization") unless user.is_a?(Organization)
          return GitHub.logger.error("org must be the advanced_security_billable_entity") unless user.advanced_security_billable_entity?
          return GitHub.logger.error("org must be using metered billing") unless user.advanced_security_metered_for_entity?
          return GitHub.logger.error("bundled offering should not be available to organizations") if user.advanced_security_products_bundled?
          return GitHub.logger.error("org must have a customer") if user.customer.nil?
          return GitHub.logger.info("skipping org excluded by feature flag") if LockMeteredUsageScheduledJob.disabled_for_actor?(user)

          writes_enabled = LockMeteredUsageScheduledJob.writes_enabled?(user)
          service = AdvancedSecurity::MeteredUsageService.new
          customer = T::must(user.customer)
          customer_id = customer.id

          skus = T.let([], T::Array[GitHub::Turboghas::SKU])
          skus << GitHub::Turboghas::SKU::CodeSecurity if user.code_security_purchased?
          skus << GitHub::Turboghas::SKU::SecretSecurity if user.secret_protection_purchased?

          skus.each do |sku|
            # If the SKU is already locked, skip the whole thing to avoid unnecessary API calls and duplicate metrics and notifications
            next if service.sku_locked_for_entity?(user, sku)

            can_proceed, reason = service.can_proceed_with_usage?(customer_id, sku)
            next if can_proceed

            log_tags = { "gh.darkship": !writes_enabled, "gh.org.name": user.name, "gh.sku": sku.to_param }
            GitHub.logger.info("org failed canProceedWithUsage for metered GHAS SKU", { "gh.reason": reason }.merge(log_tags))
            GitHub.dogstats.increment("advanced_security.metered_usage.locked",
              tags: ["sku:#{sku.to_param}", "reason:#{reason}", "darkship:#{!writes_enabled}", "entity_type:organization"])

            # Darkship metrics for warehouse
            if !writes_enabled
              message = { organization_id: user.id, sku: sku, reason: reason }
              GitHub.instrument("advanced_security_billing.darkship.ghas_metered_usage_locked", message)
            end

            next unless writes_enabled

            with_write { service.lock_sku_for_entity(user, sku, reason) }
            GitHub.logger.info("locked metered GHAS SKU for organization", log_tags)
          end
        end
      end
    end

    class BusinessesLockJob < ApplicationJob
      queue_as :advanced_security_metered_lock

      retry_on_dirty_exit
      retry_on_recoverable_exceptions

      locked_by timeout: 1.hour, key: ->(job) {
        job.arguments[0]
      }

      sig { params(job_key: String, config_value: String).void }
      def perform(job_key:, config_value:)
        Configuration::Entry
          .where({
            target_type: :Business,
            name: Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_KEY,
            value: config_value,
          })
          .find_in_batches do |batch|
            ActiveJob.perform_all_later(batch.map(&:target_id).map do |business_id|
              BusinessLockJob.new(business_id: business_id)
            end)
          end
      end
    end

    class UsersLockJob < ApplicationJob
      queue_as :advanced_security_metered_lock

      retry_on_dirty_exit
      retry_on_recoverable_exceptions

      locked_by timeout: 1.hour, key: ->(job) {
        job.arguments[0]
      }

      sig { params(job_key: String, config_value: String).void }
      def perform(job_key:, config_value:)
        Configuration::Entry
          .where({
            target_type: :User,
            name: Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_KEY,
            value: config_value,
          })
          .find_in_batches do |batch|
            ActiveJob.perform_all_later(batch.map(&:target_id).map do |user_id|
              UserLockJob.new(user_id: user_id)
            end)
          end
      end
    end

    sig { void }
    def perform
      [Configurable::AdvancedSecurityBillingConfig::GHAS_METERED, Configurable::AdvancedSecurityBillingConfig::SPLIT_METERED].each do |config_value|
        BusinessesLockJob.perform_later(job_key: job_id, config_value:)
        UsersLockJob.perform_later(job_key: job_id, config_value:)
      end
    end
  end
end
