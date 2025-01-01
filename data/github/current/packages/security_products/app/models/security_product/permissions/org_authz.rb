# typed: strict
# frozen_string_literal: true

module SecurityProduct
  module Permissions
    class OrgAuthz
      extend T::Sig

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

      # TODO: This method is used a lot, mirroring the overuse of the manage_security_products FGP.
      # Replace this method with more descriptive ones for each usage to simulate *finer* grained FGPs.
      # This will help facilitate figuring out what FGPs we need to create for https://github.com/github/security-center/issues/1334.
      sig { returns(T::Boolean) }
      def can_manage_security_products?
        async_can_manage_security_products?.sync
      end

      sig { returns(T::Boolean) }
      def can_manage_secret_scanning_settings?
        async_can_manage_secret_scanning_settings?.sync
      end


      # TODO: This method is used a lot, mirroring the overuse of the manage_security_products FGP.
      # Replace this method with more descriptive ones for each usage to simulate *finer* grained FGPs.
      # This will help facilitate figuring out what FGPs we need to create for https://github.com/github/security-center/issues/1334.
      sig { returns(Promise[T::Boolean]) }
      def async_can_manage_security_products?
        action = :manage_security_products
        async_allow?(action)
      end

      sig { returns(Promise[T::Boolean]) }
      def async_can_manage_secret_scanning_settings?
        action = :manage_secret_scanning_settings
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
