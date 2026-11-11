# typed: true
# frozen_string_literal: true

module Permissions
  module LicensePolicy
    class << self
      sig { params(user: T.nilable(User), business: T.nilable(Business)).returns(T::Boolean) }
      def can_manage_enterprise_license_policy?(user, business)
        async_can_manage_enterprise_license_policy?(user, business).sync
      end

      sig { params(user: T.nilable(User), business: T.nilable(Business)).returns(T::Boolean) }
      def can_view_enterprise_license_policy?(user, business)
        async_can_view_enterprise_license_policy?(user, business).sync
      end

      sig { params(user: T.nilable(User), repo: T.nilable(Repository)).returns(T::Boolean) }
      def can_manage_repository_license_policy?(user, repo)
        async_can_manage_repository_license_policy?(user, repo).sync
      end

      sig { params(user: T.nilable(User), repo: T.nilable(Repository)).returns(T::Boolean) }
      def can_view_repository_license_policy?(user, repo)
        async_can_view_repository_license_policy?(user, repo).sync
      end

      sig { params(user: T.nilable(User), repo: T.nilable(Repository)).returns(T::Boolean) }
      def can_view_license_compliance_alerts?(user, repo)
        async_can_view_license_compliance_alerts?(user, repo).sync
      end

      sig { params(user: T.nilable(User), repo: T.nilable(Repository)).returns(T::Boolean) }
      def can_request_license_compliance_alert_dismissal?(user, repo)
        async_can_request_license_compliance_alert_dismissal?(user, repo).sync
      end

      sig { params(user: T.nilable(User), repo: T.nilable(Repository)).returns(T::Boolean) }
      def can_review_license_compliance_alert_dismissal_request?(user, repo)
        async_can_review_license_compliance_alert_dismissal_request?(user, repo).sync
      end

      private

      sig { params(business: T.nilable(Business)).returns(T::Boolean) }
      def is_license_compliance_enabled?(business)
        return false unless GitHub.dependency_graph_enabled?
        return false if GitHub.enterprise? && !business&.advanced_security_purchased?
        return false unless FeatureFlag.vexi.enabled?(:dependency_graph_license_compliance, business, default: false)

        true
      end

      # Checks if current user is authorized to edit enterprise license policy
      # A user is authorized if they are 1. admin of enterprise
      # 2. have been granted the manage_enterprise_license_policy fgp
      # 3. have been granted the review_enterprise_license_alert_dismissal_requests fgp
      sig { params(user: T.nilable(User), business: T.nilable(Business)).returns(Promise[T::Boolean]) }
      def async_can_manage_enterprise_license_policy?(user, business)
        return Promise.resolve(T.let(false, T::Boolean)) unless business && user
        return Promise.resolve(T.let(false, T::Boolean)) unless self.is_license_compliance_enabled?(business)

        has_manage_permission = Platform::Loaders::Permissions::BatchAuthorize.load(
          action: :manage_enterprise_license_policy,
          actor: user,
          subject: business,
        )

        has_review_permission = Platform::Loaders::Permissions::BatchAuthorize.load(
          action: :review_enterprise_license_alert_dismissal_requests,
          actor: user,
          subject: business,
        )

        Promise.all([has_manage_permission, has_review_permission]).then do |results|
          results.any?(&:allow?)
        end
      end

      # Checks if current user is authorized to view enterprise license policy
      # A user is authorized if they are 1. admin of enterprise
      # 2. have been granted the manage_enterprise_license_policy fgp
      # 3. have been granted the review_enterprise_license_alert_dismissal_requests fgp
      # 4. have been granted the read_enterprise_license_policy fgp
      sig { params(user: T.nilable(User), business: T.nilable(Business)).returns(Promise[T::Boolean]) }
      def async_can_view_enterprise_license_policy?(user, business)
        return Promise.resolve(T.let(false, T::Boolean)) unless business && user
        return Promise.resolve(T.let(false, T::Boolean)) unless self.is_license_compliance_enabled?(business)

        # admin, manager, and reviewer are all covered by can_manage_enterprise_license_policy
        has_manage_permission = async_can_manage_enterprise_license_policy?(user, business)

        has_read_permission = Platform::Loaders::Permissions::BatchAuthorize.load(
          action: :read_enterprise_license_policy,
          actor: user,
          subject: business,
        )

        Promise.all([has_manage_permission, has_read_permission]).then do |results|
          results.any? do |result|
            if result.is_a?(TrueClass) || result.is_a?(FalseClass)
              result
            elsif result.respond_to?(:allow?)
              T.unsafe(result).allow?
            else
              false
            end
          end
        end
      end

      # Checks if current user is authorized to edit repository license policy
      # A user is authorized if they are 1. admin of the repository
      # 2. can_manage_enterprise_license_policy?
      sig { params(user: T.nilable(User), repo: T.nilable(Repository)).returns(Promise[T::Boolean]) }
      def async_can_manage_repository_license_policy?(user, repo)
        return Promise.resolve(T.let(false, T::Boolean)) unless user && repo && repo.business
        return Promise.resolve(T.let(false, T::Boolean)) unless self.is_license_compliance_enabled?(repo.business)

        is_repo_admin = repo.async_adminable_by?(user)
        has_manage_permission = async_can_manage_enterprise_license_policy?(user, repo.business)

        Promise.all([is_repo_admin, has_manage_permission]).then do |results|
          results.any?
        end
      end

      # Checks if current user is authorized to view repository license policy
      # A user is authorized if they are 1. reader of the repository
      # 2. can_manage_enterprise_license_policy?
      sig { params(user: T.nilable(User), repo: T.nilable(Repository)).returns(Promise[T::Boolean]) }
      def async_can_view_repository_license_policy?(user, repo)
        return Promise.resolve(T.let(false, T::Boolean)) unless user && repo && repo.business
        return Promise.resolve(T.let(false, T::Boolean)) unless self.is_license_compliance_enabled?(repo.business)

        is_repo_writer = repo.async_writable_by?(user)
        has_manage_permission = async_can_manage_enterprise_license_policy?(user, repo.business)

        Promise.all([is_repo_writer, has_manage_permission]).then do |results|
          results.any?
        end
      end

      # Checks if current user is authorized to view license compliance alerts
      # A user is authorized if they are 1. reader of the repository
      # 2. can_manage_enterprise_license_policy?
      sig { params(user: T.nilable(User), repo: T.nilable(Repository)).returns(Promise[T::Boolean]) }
      def async_can_view_license_compliance_alerts?(user, repo)
        return Promise.resolve(T.let(false, T::Boolean)) unless user && repo && repo.business
        return Promise.resolve(T.let(false, T::Boolean)) unless self.is_license_compliance_enabled?(repo.business)

        is_repo_reader = repo.async_readable_by?(user)
        has_manage_permission = async_can_manage_enterprise_license_policy?(user, repo.business)

        Promise.all([is_repo_reader, has_manage_permission]).then do |results|
          results.any?
        end
      end

      # Checks if current user is authorized to request dismissal of a license compliance alert
      # A user is authorized if they are 1. writer of the repository
      # 2. can_manage_enterprise_license_policy?
      sig { params(user: T.nilable(User), repo: T.nilable(Repository)).returns(Promise[T::Boolean]) }
      def async_can_request_license_compliance_alert_dismissal?(user, repo)
        return Promise.resolve(T.let(false, T::Boolean)) unless user && repo && repo.business
        return Promise.resolve(T.let(false, T::Boolean)) unless self.is_license_compliance_enabled?(repo.business)

        is_repo_writer = repo.async_writable_by?(user)
        has_manage_permission = async_can_manage_enterprise_license_policy?(user, repo.business)

        Promise.all([is_repo_writer, has_manage_permission]).then do |results|
          results.any?
        end
      end

      # Checks if current user is authorized to approve/deny a request to dismiss a license compliance alert
      # A user is authorized if they are 1. can_manage_enterprise_license_policy?
      sig { params(user: T.nilable(User), repo: T.nilable(Repository)).returns(Promise[T::Boolean]) }
      def async_can_review_license_compliance_alert_dismissal_request?(user, repo)
        return Promise.resolve(T.let(false, T::Boolean)) unless user && repo && repo.business
        return Promise.resolve(T.let(false, T::Boolean)) unless self.is_license_compliance_enabled?(repo.business)

        # TODO: Should this be a more complex check that takes into account the scope of the request (e.g. is the exception
        # being added to the enterprise policy, org policy, or repo policy)?
        async_can_manage_enterprise_license_policy?(user, repo.business)
      end
    end
  end
end
