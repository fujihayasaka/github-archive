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

    sig { returns(T::Boolean) }
    def self.darkship_enabled?
      FeatureFlag.vexi.enabled?("ghas_cpwu_integration_darkship", default: false)
    end

    sig { returns(T::Boolean) }
    def self.writes_enabled?
      FeatureFlag.vexi.enabled?("ghas_cpwu_integration", default: false)
    end

    class BusinessLockJob < ApplicationJob
      queue_as :advanced_security_metered_lock

      retry_on_dirty_exit
      retry_on_recoverable_exceptions

      locked_by timeout: 1.hour, key: ->(job) {
        job.arguments[0]
      }

      sig { params(business_id: Integer).void }
      def perform(business_id:)
        writes_enabled = LockMeteredUsageScheduledJob.writes_enabled?
        return unless writes_enabled || LockMeteredUsageScheduledJob.darkship_enabled?

        GitHub.logger.with_named_tags(
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.business.id": business_id,
          "gh.darkship": !writes_enabled,
        ) do
          GitHub.logger.info("begin advanced security canProceedWithUsage check for business")

          business = Business.find_by(id: business_id)
          return GitHub.logger.error("business can't be nil") if business.nil?
          return GitHub.logger.error("business must be the advanced_security_billable_entity") unless business.advanced_security_billable_entity?
          return GitHub.logger.error("business must be using metered billing") unless business.advanced_security_metered_for_entity?
          return GitHub.logger.error("business must have a customer") if business.customer.nil?

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
            can_proceed, reason = service.can_proceed_with_usage?(customer_id, sku)
            next if can_proceed

            GitHub.logger.info("business failed canProceedWithUsage for metered SKU", { "gh.sku": sku.to_param, "gh.reason": reason,  "gh.business.name": business.name })

            # If the SKU is already locked, we skip locking it again to avoid duplicate metrics and notifications
            next if service.sku_locked_for_entity?(business, sku)

            GitHub.dogstats.increment("advanced_security.metered_usage.locked",
              tags: ["sku:#{sku.to_param}", "reason:#{reason}", "darkship:#{!writes_enabled}", "entity_type:business"])

            next unless writes_enabled

            with_write { service.lock_sku_for_entity(business, sku, reason) }
          end
        end
      end
    end

    class UserLockJob < ApplicationJob
      queue_as :advanced_security_metered_lock

      retry_on_dirty_exit
      retry_on_recoverable_exceptions

      locked_by timeout: 1.hour, key: ->(job) {
        job.arguments[0]
      }

      sig { params(user_id: Integer).void }
      def perform(user_id:)
        writes_enabled = LockMeteredUsageScheduledJob.writes_enabled?
        return unless writes_enabled || LockMeteredUsageScheduledJob.darkship_enabled?

        GitHub.logger.with_named_tags(
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.user.id": user_id,
          "gh.darkship": !writes_enabled,
        ) do
          GitHub.logger.info("begin advanced security canProceedWithUsage check for organization")

          user = User.find_by(id: user_id)
          return GitHub.logger.error("user can't be nil") if user.nil?
          return GitHub.logger.error("user must be an organization") unless user.is_a?(Organization)
          return GitHub.logger.error("user must be the advanced_security_billable_entity") unless user.advanced_security_billable_entity?
          return GitHub.logger.error("user must be using metered billing") unless user.advanced_security_metered_for_entity?
          return GitHub.logger.error("bundled offering should not be available to user/organizations") if user.advanced_security_products_bundled?
          return GitHub.logger.error("user must have a customer") if user.customer.nil?

          service = AdvancedSecurity::MeteredUsageService.new
          customer = T::must(user.customer)
          customer_id = customer.id

          skus = T.let([], T::Array[GitHub::Turboghas::SKU])
          skus << GitHub::Turboghas::SKU::CodeSecurity if user.code_security_purchased?
          skus << GitHub::Turboghas::SKU::SecretSecurity if user.secret_protection_purchased?

          skus.each do |sku|
            can_proceed, reason = service.can_proceed_with_usage?(customer_id, sku)
            next if can_proceed

            GitHub.logger.info("org failed canProceedWithUsage for metered SKU", { "gh.sku": sku.to_param, "gh.reason": reason, "gh.org.name": user.name })

            # If the SKU is already locked, we skip locking it again to avoid duplicate metrics and notifications
            next if service.sku_locked_for_entity?(user, sku)

            GitHub.dogstats.increment("advanced_security.metered_usage.locked",
              tags: ["sku:#{sku.to_param}", "reason:#{reason}", "darkship:#{!writes_enabled}", "entity_type:organization"])

            next unless writes_enabled

            with_write { service.lock_sku_for_entity(user, sku, reason) }
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
        return unless LockMeteredUsageScheduledJob.darkship_enabled? || LockMeteredUsageScheduledJob.writes_enabled?

        Configuration::Entry
          .where({
            target_type: :Business,
            name: Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_KEY,
            value: config_value,
          })
          .find_in_batches do |batch|
            # Check feature flags on every batch in case we need to quickly disable enqueuing
            return unless LockMeteredUsageScheduledJob.darkship_enabled? || LockMeteredUsageScheduledJob.writes_enabled?

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
        return unless LockMeteredUsageScheduledJob.darkship_enabled? || LockMeteredUsageScheduledJob.writes_enabled?

        Configuration::Entry
          .where({
            target_type: :User,
            name: Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_KEY,
            value: config_value,
          })
          .find_in_batches do |batch|
            # Check feature flags on every batch in case we need to quickly disable enqueuing
            return unless LockMeteredUsageScheduledJob.darkship_enabled? || LockMeteredUsageScheduledJob.writes_enabled?

            ActiveJob.perform_all_later(batch.map(&:target_id).map do |user_id|
              UserLockJob.new(user_id:)
            end)
          end
      end
    end

    sig { void }
    def perform
      return unless self.class.writes_enabled? || self.class.darkship_enabled?

      [Configurable::AdvancedSecurityBillingConfig::GHAS_METERED, Configurable::AdvancedSecurityBillingConfig::SPLIT_METERED].each do |config_value|
        BusinessesLockJob.perform_later(job_key: job_id, config_value:)
        UsersLockJob.perform_later(job_key: job_id, config_value:)
      end
    end
  end
end
