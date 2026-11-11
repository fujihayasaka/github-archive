# typed: true
# frozen_string_literal: true

module Permissions
  module LicensePolicy
    sig { params(user: T.nilable(User), business: T.nilable(Business)).returns(T::Boolean) }
    def self.can_manage_enterprise_license_policy?(user, business)
      async_can_manage_enterprise_license_policy?(user, business).sync
    end

    # Checks if current user is authorized to edit license policy
    # A user is authorized if they are 1. admin of enterprise or 2. have been granted the manage_enterprise_license_policy fgp
    sig { params(user: T.nilable(User), business: T.nilable(Business)).returns(Promise[T::Boolean]) }
    def self.async_can_manage_enterprise_license_policy?(user, business)
      return Promise.resolve(T.let(false, T::Boolean)) unless business&.feature_flag_enabled?(:dependency_graph_license_compliance, default: false)

      Platform::Loaders::Permissions::BatchAuthorize.load(
        action: :manage_enterprise_license_policy,
        actor: user,
        subject: business,
      ).then(&:allow?)
    end

    sig { params(business: T.nilable(Business)).returns(T::Boolean) }
    def self.is_license_compliance_enabled?(business)
      return false unless GitHub.dependency_graph_enabled?
      return false if GitHub.enterprise? && !business&.advanced_security_purchased?
      return false unless FeatureFlag.vexi.enabled?(:dependency_graph_license_compliance, business, default: false)

      true
    end

    sig { params(user: T.nilable(User), business: T.nilable(Business)).returns(T::Boolean) }
    def self.can_access_license_policy?(user, business)
      is_license_compliance_enabled?(business) && can_manage_enterprise_license_policy?(user, business)
    end

    sig { params(user: T.nilable(User), repo: T.nilable(Repository)).returns(T::Boolean) }
    def self.can_manage_repository_license_policy?(user, repo)
      return false unless repo && user
      return false unless is_license_compliance_enabled?(repo.business)

      repo.adminable_by?(user) || !!repo.business&.adminable_by?(user)
    end
  end
end
