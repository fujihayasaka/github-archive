# typed: strict
# frozen_string_literal: true

module SecurityProduct
  module Permissions
    class RepoAuthz
      sig { params(subject: ::Repository, actor: T.nilable(::User)).void }
      def initialize(subject, actor:)
        @actor = actor
        @subject = subject
      end

      # TODO: This method is used a lot, mirroring the overuse of the manage_security_products FGP.
      # Replace this method with more descriptive ones for each usage to simulate *finer* grained FGPs.
      # This will help facilitate figuring out what FGPs we need to create for https://github.com/github/security-center/issues/1334.
      sig { returns(T::Boolean) }
      def can_manage_security_products?
        async_can_manage_security_products?.sync
      end

      # TODO: This method is used a lot, mirroring the overuse of the manage_security_products FGP.
      # Replace this method with more descriptive ones for each usage to simulate *finer* grained FGPs.
      # This will help facilitate figuring out what FGPs we need to create for https://github.com/github/security-center/issues/1334.
      sig { returns(Promise[T::Boolean]) }
      def async_can_manage_security_products?
        action = :manage_security_products

        @subject.async_owner.then do |owner|
          next @subject.async_adminable_by?(@actor) unless owner.is_a?(::Organization)
          async_allow?(action)
        end
      end

      sig { returns(T::Boolean) }
      def manage_repo_advanced_security_enablement_blocked_by_policy?
        policy_blocking_action?(action: :manage_advanced_security_enablement)
      end

      sig { returns(T::Boolean) }
      def manage_repo_code_security_enablement_blocked_by_policy?
        policy_blocking_action?(action: :manage_code_security_enablement)
      end

      sig { returns(T::Boolean) }
      def manage_repo_dependabot_alerts_enablement_blocked_by_policy?
        policy_blocking_action?(action: :manage_dependabot_alerts_enablement)
      end

      sig { returns(T::Boolean) }
      def manage_repo_secret_scanning_settings_blocked_by_policy?
        policy_blocking_action?(action: :manage_secret_scanning_settings)
      end

      private

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def actor_tags
        {
          "enduser.id": @actor&.display_login,
          "gh.enduser.id": @actor&.id,
          "gh.enduser.login": @actor&.display_login,
        }
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def subject_tags
        {
          "gh.repo.id": @subject.id,
          "gh.repo.name": @subject.name,
          "gh.repo.name_with_owner": @subject.name_with_display_owner,
        }
      end

      sig { params(action: Symbol, context: T.nilable(T::Hash[Symbol, T.untyped])).returns(Promise[T::Boolean]) }
      def async_allow?(action, context: nil)
        return Promise.resolve(T.let(false, T::Boolean)) unless @actor&.user? # Reject bots
        return Promise.resolve(T.let(false, T::Boolean)) if @subject.advisory_workspace? # There's no security pages in advisory workspace/temporary fork repos

        GitHub.logger.with_named_tags(**actor_tags, **subject_tags, "gh.authzd.attributes.action": action) do
          GitHub.logger.info("Check authorization", "code.namespace": self.class.name, "code.function": __method__)
          Platform::Loaders::Permissions::BatchAuthorize.load(
            action:,
            actor: @actor,
            subject: @subject,
            context:,
          ).then(&:allow?)
        end
      end

      sig { params(action: Symbol).returns(T::Boolean) }
      def policy_blocking_action?(action:)
        owner = @subject.owner
        business = owner&.business
        business ||= Business.enterprise_managed_business_for(resource: @subject)
        business ||= GitHub.global_business if GitHub.single_business_environment?
        return false unless business # do not block for non-business repos

        allow_repo_admins =
          case action
          when :manage_advanced_security_enablement
            business.repo_admins_can_modify_advanced_security_enablement?
          when :manage_code_security_enablement
            business.repo_admins_can_modify_code_security_enablement?
          when :manage_dependabot_alerts_enablement
            business.repo_admins_can_modify_dependabot_alerts_enablement?
          when :manage_secret_scanning_settings
            business.repo_admins_can_modify_secret_scanning_settings?
          else
            raise ArgumentError, "Unknown action: #{action}"
          end

        # If there's no blocking policy, then repo admins are able to make these changes,
        # and are not blocked by any policy.
        return false if allow_repo_admins

        # We haven't updated the policies to support user-owned repositories yet,
        # so we need to handle them here before we reach out to authzd.
        if owner&.user?
          return false unless @subject.adminable_by?(@actor)
          return !business.owner?(@actor)
        end

        # For org owned repositories, check for appropriate FGPs
        can_manage, can_manage_ignoring_policy = Promise.all([
          async_allow?(action, context: { allow_repo_admins: }),
          async_allow?(action, context: { allow_repo_admins: true }),
        ]).sync

        !can_manage && can_manage_ignoring_policy
      end
    end
  end
end
