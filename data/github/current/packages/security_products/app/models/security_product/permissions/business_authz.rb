# typed: strict
# frozen_string_literal: true

module SecurityProduct
  module Permissions
    class BusinessAuthz
      sig { params(subject: ::Business, actor: T.nilable(::User)).void }
      def initialize(subject, actor:)
        @actor = actor
        @subject = subject
      end

      sig { returns(T::Boolean) }; def can_view_code_security_policies?; can_manage_enterprise_security_products?; end
      sig { returns(T::Boolean) }; def can_modify_code_security_policies?; can_manage_enterprise_security_products?; end
      sig { returns(T::Boolean) }; def can_view_enterprise_bypass_requests_list?; can_manage_enterprise_security_products?; end
      sig { returns(T::Boolean) }
      def can_view_code_security_settings?
        # Until enterprise teams have been reimplemented without org team sync, we will only allow business owners.
        # https://github.com/github/security-center/issues/6109
        if EnterpriseTeam.enabled_for_organization_security_manager?(@subject) &&
          !EnterpriseTeam.can_sync_all_orgs?(business: @subject)

          @subject.owner?(@actor)
        else
          can_manage_enterprise_security_products?
        end
      end
      sig { returns(T::Boolean) }
      def can_modify_code_security_settings?
        # Until enterprise teams have been reimplemented without org team sync, we will only allow business owners.
        # https://github.com/github/security-center/issues/6109
        if EnterpriseTeam.enabled_for_organization_security_manager?(@subject) &&
          !EnterpriseTeam.can_sync_all_orgs?(business: @subject)

          @subject.owner?(@actor)
        else
          can_manage_enterprise_security_products?
        end
      end
      sig { returns(T::Boolean) }; def can_view_user_owned_repository_alerts?; can_manage_enterprise_security_products?; end
      sig { returns(T::Boolean) }; def can_unlock_user_owned_repositories?; can_manage_enterprise_security_products?; end

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
          "gh.business.id": @subject.id,
          "gh.business.name": @subject.name,
        }
      end

      sig { params(action: Symbol, context: T.nilable(T::Hash[Symbol, T.untyped])).returns(Promise[T::Boolean]) }
      def async_allow?(action, context: nil)
        return Promise.resolve(T.let(false, T::Boolean)) unless @actor

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

      sig { returns(T::Boolean) }
      def can_manage_enterprise_security_products?
        if @subject.erp_feature_enabled?(:enterprise_teams_esm)
          return false if @actor.nil?
          Authz.domain.check_allowed(@actor, :manage_enterprise_security_products, @subject)
        else
          async_can_manage_enterprise_security_products?.sync
        end
      end

      sig { returns(Promise[T::Boolean]) }
      def async_can_manage_enterprise_security_products?
        context = {
          "business.enterprise_teams.for_user": EnterpriseTeam.all_visible_team_ids_for(@actor, business_ids: [@subject.id])
        } if @actor
        async_allow?(:manage_enterprise_security_products, context:)
      end
    end
  end
end
