# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  class TenantValidationHelper
    extend T::Helpers

    abstract!
    sealed!

    sig { params(owner: T.any(::User, Business)).returns(T::Boolean) }
    def self.is_owner_in_scope?(owner)
      if owner.is_a?(Business)
        return true if GitHub.enterprise?
        return true if owner.plan.business_plus?
        return true if owner.advanced_security_purchased?
      elsif owner.organization?
        return true if GitHub.enterprise?
        return true if owner.plan.business_plus? || owner.business&.plan&.business_plus?
        return true if owner.advanced_security_purchased?
      elsif owner.user?
        if AdvancedSecurity::Features::User::AdvancedSecurity.new(owner).feature_available?
          return true if GitHub.enterprise?
          return true if owner.is_enterprise_managed?
        end
      end

      false
    end

    sig { params(owner_id: Integer).returns(T::Boolean) }
    def self.should_handle_repository_lifecycle_events?(owner_id)
      owner = ::User.find_by(id: owner_id)
      unless owner.present?
        GitHub.logger.warn(
          "Owner not found",
          "code.namespace": self.name,
          "code.function": __method__,
          "gh.owner.id": owner_id,
        )
        return false
      end

      return false unless is_owner_in_scope?(owner)

      Initialization.for(owner).initialized?(type: Initialization::Type::RepositoryMetadata)
    end

    sig { params(repository_owner: T.nilable(::User)).returns(T::Boolean) }
    def self.should_handle_feature_enablement_events?(repository_owner)
      return false if repository_owner.nil?
      return false unless is_owner_in_scope?(repository_owner)

      Initialization.for(repository_owner).initialized?(type: Initialization::Type::FeatureEnablement)
    end

    sig { params(repository_owner: T.nilable(::User)).returns(T::Boolean) }
    def self.should_handle_code_scanning_alert_events?(repository_owner)
      return false unless repository_owner&.organization?
      return false unless is_owner_in_scope?(repository_owner)

      Initialization.for(repository_owner).initialized?(type: Initialization::Type::CodeScanningAlert)
    end

    sig { params(repository_owner: T.nilable(::User)).returns(T::Boolean) }
    def self.should_handle_code_scanning_pull_request_alert?(repository_owner)
      return false unless repository_owner&.organization?
      is_owner_in_scope?(repository_owner)
    end

    sig { params(repository_owner: T.nilable(::User)).returns(T::Boolean) }
    def self.should_handle_secret_scanning_alert_events?(repository_owner)
      return false if repository_owner.nil?
      return false unless is_owner_in_scope?(repository_owner)

      Initialization.for(repository_owner).initialized?(type: Initialization::Type::SecretScanningAlert)
    end

    sig { params(repository: ::Repository).returns(T::Boolean) }
    def self.should_handle_dependabot_alert_events?(repository)
      owner = repository.owner

      return false unless owner.is_a?(::Organization)
      return false unless is_owner_in_scope?(owner)

      Initialization.for(owner).initialized?(type: Initialization::Type::DependabotAlerts)
    end
  end
end
