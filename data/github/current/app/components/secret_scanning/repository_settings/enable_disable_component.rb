# typed: true
# frozen_string_literal: true

module SecretScanning
  module RepositorySettings
    class EnableDisableComponent < ApplicationComponent
      include SecretScanning::Features::FeatureFlagHelper

      sig { params(repository: Repository, enabled: T::Boolean, update_path: String).void }
      def initialize(repository:, enabled:, update_path:)
        @repository = repository
        @enabled = enabled
        @update_path = update_path
      end

      private

      sig { returns(Repository) }
      attr_reader :repository

      sig { returns(T::Boolean) }
      attr_reader :enabled

      sig { returns(String) }
      attr_reader :update_path

      sig { returns(String) }
      def button_text
        enabled ? "Disable" : "Enable"
      end

      sig { returns(Integer) }
      def input_value
        enabled ? 0 : 1
      end

      # Only show this license increase, as a bullet item, if the repo
      # is part of non-Team plan
      sig { returns(T::Boolean) }
      memoize def show_license_increase?
        return false unless @repository.owner&.business.present?

        secret_scanning_available?
      end

      sig { returns(T::Boolean) }
      memoize def show_cost_breakdown?
        # Only show for Teams
        return false if @repository.owner&.business.present?

        # Must be unbundled
        return false if repository.advanced_security_products_bundled?

        secret_scanning_available?
      end

      # Only shown to team orgs since they see a cost breakdown that includes a monetary amount
      sig { returns(T::Boolean) }
      memoize def show_trial_banner?
        return false unless secret_protection_trial

        T.must(secret_protection_trial).enabled?
      end

      sig { returns(T::Hash[Symbol, T.any(Integer, String)]) }
      memoize def cost_breakdown
        result = T.let({}, T::Hash[Symbol, T.any(Integer, String)])
        owner = repository.owner
        return { total: Billing::Money.new(0).format, count: 0 } unless owner

        cost = if increased_license_usage > 0
          owner.advanced_security_price_for_sku(sku: "ghas_secret_protection_licenses", seats: 1)
        else
          return { total: Billing::Money.new(0).format, count: 0 }
        end

        { per_license_cost: cost.format, count: increased_license_usage, total: (cost * increased_license_usage).format }
      end

      sig { returns(Integer) }
      memoize def increased_license_usage
        owner = repository.owner
        return 0 unless owner

        owner.secret_protection.seat_usage_increase_if_enabled_for_repo(repository)
      end

      sig { returns(T::Boolean) }
      memoize def secret_scanning_available?
        SecretScanning::Features::AdvancedSecurityHelper.secret_scanning_available?(@repository)
      end

      sig { returns(T.nilable(Billing::Types::OrgOrBusiness)) }
      memoize def billable_entity
        owner = @repository.owner
        return nil unless owner

        billable_entity = owner.advanced_security_billable_entity
        return nil unless billable_entity

        billable_entity
      end

      sig { returns(String) }
      memoize def entity_type
        case billable_entity
        when ::Organization
          "organization"
        when ::Business
          "business"
        else
          ""
        end
      end

      sig { returns(T.nilable(EnterpriseCloudOnboard::SecretProtectionTrial)) }
      memoize def secret_protection_trial
        return nil unless billable_entity

        EnterpriseCloudOnboard::SecretProtectionTrial.new(billable_entity: T.must(billable_entity))
      end
    end
  end
end
