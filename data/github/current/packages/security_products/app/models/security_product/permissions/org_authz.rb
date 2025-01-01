# typed: strict
# frozen_string_literal: true

module SecurityProduct
  module Permissions
    class OrgAuthz
      sig { params(subject: ::Organization, actor: T.nilable(::User)).void }
      def initialize(subject, actor:)
        @actor = actor
        @subject = subject
      end

      sig { returns(T::Boolean) }
      def can_view_security_managers?
        async_can_view_security_managers?.sync
      end

      sig { returns(Promise[T::Boolean]) }
      def async_can_view_security_managers?
        async_allow?(:view_security_managers)
      end

      sig { returns(T::Boolean) }
      def can_add_security_managers?
        async_can_add_security_managers?.sync
      end

      sig { returns(Promise[T::Boolean]) }
      def async_can_add_security_managers?
        async_allow?(:add_security_managers)
      end

      sig { returns(T::Boolean) }
      def can_remove_security_managers?
        async_can_remove_security_managers?.sync
      end

      sig { returns(Promise[T::Boolean]) }
      def async_can_remove_security_managers?
        async_allow?(:remove_security_managers)
      end

      sig { returns(T::Boolean) }
      def can_manage_org_security_products?
        async_can_manage_org_security_products?.sync
      end

      sig { returns(T::Boolean) }
      def can_manage_secret_scanning_settings?
        async_can_manage_secret_scanning_settings?.sync
      end

      sig { returns(Promise[T::Boolean]) }
      def async_can_manage_org_security_products?
        if FeatureFlag.vexi.enabled?("security_products_fgp_split", default: false)
          action = :manage_org_security_products
        else
          action = :manage_security_products
        end
        async_allow?(action)
      end

      # TODO: Deprecated - use can_manage_org_security_products? instead
      # Remove this when cleaning up security_products_fgp_split feature flag
      sig { returns(T::Boolean) }
      def can_manage_security_products?
        can_manage_org_security_products?
      end

      # TODO: Deprecated - use async_can_manage_org_security_products? instead
      # Remove this when cleaning up security_products_fgp_split feature flag
      sig { returns(Promise[T::Boolean]) }
      def async_can_manage_security_products?
        async_can_manage_org_security_products?
      end

      sig { returns(Promise[T::Boolean]) }
      def async_can_manage_secret_scanning_settings?
        action = :manage_secret_scanning_settings
        async_allow?(action)
      end

      sig { returns(T::Boolean) }
      def can_view_all_alerts?
        return false unless @actor
        result = Authz.domain.check_multiple_permissions(
          @actor,
          [
            :read_code_scanning,
            :view_dependabot_alerts,
            :view_secret_scanning_alerts,
          ],
          @subject
        )

        result.values.all?
      end

      sig { returns(T::Boolean) }
      def can_view_security_configurations?
        async_can_view_security_configurations?.sync
      end

      sig { returns(Promise[T::Boolean]) }
      def async_can_view_security_configurations?
        action = :manage_org_security_products
        async_allow?(action)
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
          "gh.org.id": @subject.id,
          "gh.org.login": @subject.display_login,
        }
      end

      sig { params(action: Symbol).returns(Promise[T::Boolean]) }
      def async_allow?(action)
        return Promise.resolve(T.let(false, T::Boolean)) unless @actor

        GitHub.logger.with_named_tags(**actor_tags, **subject_tags, "gh.authzd.attributes.action": action) do
          GitHub.logger.info("Check authorization", "code.namespace": self.class.name, "code.function": __method__)
          Platform::Loaders::Permissions::BatchAuthorize.load(action:, actor: @actor, subject: @subject).then(&:allow?)
        end
      end
    end
  end
end
