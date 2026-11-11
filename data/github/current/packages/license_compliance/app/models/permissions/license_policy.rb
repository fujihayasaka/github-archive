# typed: true
# frozen_string_literal: true

module Permissions
  # License-compliance permissions for the EOSLM migration
  # See https://github.com/github/dependency-graph/issues/11858 for context.
  #
  # Each `can_X?` method returns the union of EOSLM (new) grants and the
  # deprecated pre-EOSLM grants. Deprecated grants are guarded by an
  # `unless eoslm_switch_enabled?` block inside each method and can be deleted
  # in a single step when removing the dependency_graph_eoslm_switch feature flag.
  module LicensePolicy
    class << self
      # Checks if current user is authorized to edit enterprise license policy
      # A user is authorized if they are 1. admin of enterprise
      # 2. have been granted the edit_enterprise_license_policy fgp (new)
      # 3. have been granted the manage_enterprise_license_policy fgp (deprecated)
      # 4. have been granted the review_enterprise_license_alert_dismissal_requests fgp (deprecated)
      #
      # When dependency_graph_eoslm_switch is enabled, items 3 and 4 no longer apply.
      # New FGPs (item 2) are checked via generic authzd policies (Authz.domain).
      # Deprecated FGPs (items 3, 4) are checked via custom authzd policies (BatchAuthorize).
      sig { params(user: T.nilable(User), business: T.nilable(Business)).returns(T::Boolean) }
      def can_manage_enterprise_license_policy?(user, business)
        return false unless business && user
        return false unless self.is_license_compliance_enabled?(business)

        # New FGP — always checked via generic policy
        return true if Authz.domain.check_allowed(user, :edit_enterprise_license_policy, business)

        # Deprecated FGPs — only when EOSLM switch is off
        unless eoslm_switch_enabled?(business)
          return [
            async_user_has_business_fgp?(user, business, :manage_enterprise_license_policy),
            async_user_has_business_fgp?(user, business, :review_enterprise_license_alert_dismissal_requests),
          ].map(&:sync).any?
        end

        false
      end

      # Checks if current user is authorized to view enterprise license policy
      # A user is authorized if they are 1. admin of enterprise
      # 2. have been granted the edit_enterprise_license_policy fgp (new)
      # 3. have been granted the manage_enterprise_license_policy fgp (deprecated)
      # 4. have been granted the review_enterprise_license_alert_dismissal_requests fgp (deprecated)
      # 5. have been granted the view_enterprise_license_policy fgp (new)
      # 6. have been granted the read_enterprise_license_policy fgp (deprecated)
      #
      # When dependency_graph_eoslm_switch is enabled, items 3, 4, and 6 no longer apply.
      # New FGPs (items 2, 5) are checked via generic authzd policies (Authz.domain).
      # Deprecated FGPs (items 3, 4, 6) are checked via custom authzd policies (BatchAuthorize).
      sig { params(user: T.nilable(User), business: T.nilable(Business)).returns(T::Boolean) }
      def can_view_enterprise_license_policy?(user, business)
        return false unless business && user
        return false unless self.is_license_compliance_enabled?(business)

        # New FGPs — always checked via generic policy
        results = Authz.domain.check_multiple_permissions(
          user,
          [:edit_enterprise_license_policy, :view_enterprise_license_policy],
          business
        )
        return true if results.values.any?

        # Deprecated FGPs — only when EOSLM switch is off
        unless eoslm_switch_enabled?(business)
          return [
            async_user_has_business_fgp?(user, business, :manage_enterprise_license_policy),
            async_user_has_business_fgp?(user, business, :review_enterprise_license_alert_dismissal_requests),
            async_user_has_business_fgp?(user, business, :read_enterprise_license_policy),
          ].map(&:sync).any?
        end

        false
      end

      # Checks if current user is authorized to view license compliance alerts at the
      # organization level.
      # A user is authorized if they have been granted the
      # 1. review_license_compliance_closure_requests org fgp
      # 2. view_license_compliance_closure_requests org fgp
      #
      # Checked via generic authzd policies (Authz.domain).
      sig { params(user: T.nilable(User), organization: T.nilable(Organization)).returns(T::Boolean) }
      def can_view_organization_license_compliance_alerts?(user, organization)
        return false unless user && organization
        return false unless self.is_license_compliance_enabled?(organization.business)

        results = Authz.domain.check_multiple_permissions(
          user,
          [:review_license_compliance_closure_requests, :view_license_compliance_closure_requests],
          organization
        )
        results.values.any?
      end

      # Checks if current user is authorized to review license compliance
      # alert dismissal requests at the organization level.
      # A user is authorized if they have been granted the
      # 1. review_license_compliance_closure_requests org fgp
      #
      # Checked via generic authzd policies (Authz.domain).
      sig { params(user: T.nilable(User), organization: T.nilable(Organization)).returns(T::Boolean) }
      def can_review_organization_license_compliance_alerts?(user, organization)
        return false unless user && organization
        return false unless self.is_license_compliance_enabled?(organization.business)

        Authz.domain.check_allowed(user, :review_license_compliance_closure_requests, organization)
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

      sig { params(business: T.nilable(Business)).returns(T::Boolean) }
      def is_license_compliance_enabled?(business)
        return false unless GitHub.dependency_graph_enabled?
        return false if GitHub.enterprise?
        return false unless business&.advanced_security_purchased?
        return false unless FeatureFlag.vexi.enabled?(:dependency_graph_license_compliance, business, default: false)

        true
      end

      private

      # Checks if current user is authorized to edit repository license policy
      # A user is authorized if they are 1. admin of the repository (deprecated)
      # 2. have been granted the manage_enterprise_license_policy fgp (deprecated)
      # 3. have been granted the review_enterprise_license_alert_dismissal_requests fgp (deprecated)
      # 4. have been granted the review_license_compliance_closure_requests fgp (new)
      #
      # When dependency_graph_eoslm_switch is enabled, items 1, 2, and 3 no longer apply.
      sig { params(user: T.nilable(User), repo: T.nilable(Repository)).returns(Promise[T::Boolean]) }
      def async_can_manage_repository_license_policy?(user, repo)
        return Promise.resolve(T.let(false, T::Boolean)) unless user && repo && repo.business
        return Promise.resolve(T.let(false, T::Boolean)) unless self.is_license_compliance_enabled?(repo.business)

        business = T.must(repo.business)

        promises = T.let([
          async_user_has_org_fgp?(user, repo_organization(repo), :review_license_compliance_closure_requests),
        ], T::Array[Promise[T::Boolean]])

        unless eoslm_switch_enabled?(repo)
          promises << repo.async_adminable_by?(user)
          promises << async_user_has_business_fgp?(user, business, :manage_enterprise_license_policy)
          promises << async_user_has_business_fgp?(user, business, :review_enterprise_license_alert_dismissal_requests)
        end

        Promise.all(promises).then { |results| T.let(results.any?, T::Boolean) }
      end

      # Checks if current user is authorized to view repository license policy
      # A user is authorized if they are 1. writer of the repository
      # 2. have been granted the manage_enterprise_license_policy fgp (deprecated)
      # 3. have been granted the review_enterprise_license_alert_dismissal_requests fgp (deprecated)
      # 4. have been granted the view_repository_license_policy fgp (new)
      #
      # When dependency_graph_eoslm_switch is enabled, items 2 and 3 no longer apply.
      sig { params(user: T.nilable(User), repo: T.nilable(Repository)).returns(Promise[T::Boolean]) }
      def async_can_view_repository_license_policy?(user, repo)
        return Promise.resolve(T.let(false, T::Boolean)) unless user && repo && repo.business
        return Promise.resolve(T.let(false, T::Boolean)) unless self.is_license_compliance_enabled?(repo.business)

        business = T.must(repo.business)

        promises = T.let([
          repo.async_writable_by?(user),
          async_user_has_repo_fgp?(user, repo, :view_repository_license_policy),
        ], T::Array[Promise[T::Boolean]])

        unless eoslm_switch_enabled?(repo)
          promises << async_user_has_business_fgp?(user, business, :manage_enterprise_license_policy)
          promises << async_user_has_business_fgp?(user, business, :review_enterprise_license_alert_dismissal_requests)
        end

        Promise.all(promises).then { |results| T.let(results.any?, T::Boolean) }
      end

      # Checks if current user is authorized to view license compliance alerts
      # A user is authorized if they are 1. reader of the repository
      # 2. have been granted the manage_enterprise_license_policy fgp (deprecated)
      # 3. have been granted the review_enterprise_license_alert_dismissal_requests fgp (deprecated)
      # 4. have been granted the review_license_compliance_closure_requests fgp (new)
      # 5. have been granted the view_license_compliance_closure_requests fgp (new)
      #
      # When dependency_graph_eoslm_switch is enabled, items 2 and 3 no longer apply.
      sig { params(user: T.nilable(User), repo: T.nilable(Repository)).returns(Promise[T::Boolean]) }
      def async_can_view_license_compliance_alerts?(user, repo)
        return Promise.resolve(T.let(false, T::Boolean)) unless user && repo && repo.business
        return Promise.resolve(T.let(false, T::Boolean)) unless self.is_license_compliance_enabled?(repo.business)

        business = T.must(repo.business)
        org = repo_organization(repo)

        promises = T.let([
          repo.async_readable_by?(user),
          async_user_has_org_fgp?(user, org, :review_license_compliance_closure_requests),
          async_user_has_org_fgp?(user, org, :view_license_compliance_closure_requests),
        ], T::Array[Promise[T::Boolean]])

        unless eoslm_switch_enabled?(repo)
          promises << async_user_has_business_fgp?(user, business, :manage_enterprise_license_policy)
          promises << async_user_has_business_fgp?(user, business, :review_enterprise_license_alert_dismissal_requests)
        end

        Promise.all(promises).then { |results| T.let(results.any?, T::Boolean) }
      end

      # Checks if current user is authorized to request dismissal of a license compliance alert
      # A user is authorized if they are 1. writer of the repository
      # 2. have been granted the manage_enterprise_license_policy fgp (deprecated)
      # 3. have been granted the review_enterprise_license_alert_dismissal_requests fgp (deprecated)
      # 4. have been granted the review_license_compliance_closure_requests fgp (new)
      #
      # When dependency_graph_eoslm_switch is enabled, items 2 and 3 no longer apply.
      sig { params(user: T.nilable(User), repo: T.nilable(Repository)).returns(Promise[T::Boolean]) }
      def async_can_request_license_compliance_alert_dismissal?(user, repo)
        return Promise.resolve(T.let(false, T::Boolean)) unless user && repo && repo.business
        return Promise.resolve(T.let(false, T::Boolean)) unless self.is_license_compliance_enabled?(repo.business)

        business = T.must(repo.business)

        promises = T.let([
          repo.async_writable_by?(user),
          async_user_has_org_fgp?(user, repo_organization(repo), :review_license_compliance_closure_requests),
        ], T::Array[Promise[T::Boolean]])

        unless eoslm_switch_enabled?(repo)
          promises << async_user_has_business_fgp?(user, business, :manage_enterprise_license_policy)
          promises << async_user_has_business_fgp?(user, business, :review_enterprise_license_alert_dismissal_requests)
        end

        Promise.all(promises).then { |results| T.let(results.any?, T::Boolean) }
      end

      # Checks if current user is authorized to approve/deny a request to dismiss a license compliance alert
      # A user is authorized if they 1. have been granted the manage_enterprise_license_policy fgp (deprecated)
      # 2. have been granted the review_enterprise_license_alert_dismissal_requests fgp (deprecated)
      # 3. have been granted the review_license_compliance_closure_requests fgp (new)
      #
      # When dependency_graph_eoslm_switch is enabled, items 1 and 2 no longer apply.
      # This method will then be a duplicate of async_can_manage_repository_license_policy?
      # We should consolidate the two methods when that happens.
      sig { params(user: T.nilable(User), repo: T.nilable(Repository)).returns(Promise[T::Boolean]) }
      def async_can_review_license_compliance_alert_dismissal_request?(user, repo)
        return Promise.resolve(T.let(false, T::Boolean)) unless user && repo && repo.business
        return Promise.resolve(T.let(false, T::Boolean)) unless self.is_license_compliance_enabled?(repo.business)

        business = T.must(repo.business)

        promises = T.let([
          async_user_has_org_fgp?(user, repo_organization(repo), :review_license_compliance_closure_requests),
        ], T::Array[Promise[T::Boolean]])

        unless eoslm_switch_enabled?(repo)
          promises << async_user_has_business_fgp?(user, business, :manage_enterprise_license_policy)
          promises << async_user_has_business_fgp?(user, business, :review_enterprise_license_alert_dismissal_requests)
        end

        Promise.all(promises).then { |results| T.let(results.any?, T::Boolean) }
      end

      sig { params(subject: T.any(Business, Repository)).returns(T::Boolean) }
      def eoslm_switch_enabled?(subject)
        if subject.is_a?(Repository)
          FeatureFlag.vexi.enabled?(:dependency_graph_eoslm_switch, subject, repo_organization(subject), subject.business, default: false)
        else
          FeatureFlag.vexi.enabled?(:dependency_graph_eoslm_switch, subject, default: false)
        end
      end

      sig { params(user: User, business: Business, action: Symbol).returns(Promise[T::Boolean]) }
      def async_user_has_business_fgp?(user, business, action)
        Platform::Loaders::Permissions::BatchAuthorize.load(
          action: action,
          actor: user,
          subject: business,
        ).then { |decision| T.let(T.unsafe(decision).allow?, T::Boolean) }
      end

      # Returns Promise.resolve(false) when `org` is not an Organization
      # (e.g., user-owned repos). The org-scoped BatchAuthorize loader requires
      # an Organization subject.
      sig { params(user: User, org: T.nilable(Organization), action: Symbol).returns(Promise[T::Boolean]) }
      def async_user_has_org_fgp?(user, org, action)
        return Promise.resolve(T.let(false, T::Boolean)) unless org

        Platform::Loaders::Permissions::BatchAuthorize.load(
          action: action,
          actor: user,
          subject: org,
        ).then { |decision| T.let(T.unsafe(decision).allow?, T::Boolean) }
      end

      sig { params(user: User, repo: Repository, action: Symbol).returns(Promise[T::Boolean]) }
      def async_user_has_repo_fgp?(user, repo, action)
        Platform::Loaders::Permissions::BatchAuthorize.load(
          action: action,
          actor: user,
          subject: repo,
        ).then { |decision| T.let(T.unsafe(decision).allow?, T::Boolean) }
      end

      # Returns the repo's owning Organization, or nil for user-owned repos.
      sig { params(repo: Repository).returns(T.nilable(Organization)) }
      def repo_organization(repo)
        owner = repo.owner
        owner.is_a?(Organization) ? owner : nil
      end
    end
  end
end
