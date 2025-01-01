# typed: strict
# frozen_string_literal: true

module EnterpriseNavigation
  module Links
    module SharedDependency
      extend T::Helpers
      include GitHub::Memoizer

      sig { returns T.nilable(Business) }
      memoize def business
        @business = T.let(@business || nil, T.nilable(Business))
      end

      sig { returns T.nilable(User) }
      memoize def user
        @user = T.let(@user || nil, T.nilable(User))
      end

      sig { returns T::Boolean }
      memoize def business_owner?
        business&.owner?(user)
      end

      sig { params(fgp: T.untyped).returns(T::Boolean) }
      def user_has_business_permission?(fgp)
        return false unless business && user && fgp
        Authz.domain.check_allowed(T.must(user), fgp, T.must(business))
      end

      sig { returns T::Boolean }
      memoize def basic_account?
        @business&.seats_plan_basic? || false
      end

      sig { returns T::Boolean }
      memoize def member_of_owned_org?
        business&.user_is_member_of_owned_org?(user)
      end

      sig { returns T::Boolean }
      memoize def business_org_owner?
        @business&.user_is_owner_of_owned_org?(user)
      end

      sig { returns T::Boolean }
      memoize def business_billing_manager?
        @business&.billing_manager?(user)
      end

      sig { returns(T::Boolean) }
      memoize def show_code_security_alerts_code_scanning_menu_item?
        return false unless SecurityCenter::SecurityFeatures.code_scanning_enabled_for_instance?
        return false if GitHub.enterprise? && !@business&.advanced_security_purchased?
        true
      end

      sig { returns(T::Boolean) }
      memoize def show_code_security_dismissal_requests_code_scanning_menu_item?
        return false unless SecurityCenter::SecurityFeatures.code_scanning_enabled_for_instance?
        return false if GitHub.enterprise? && !@business&.advanced_security_purchased?
        return false unless business&.feature_enabled?(:code_scanning_enterprise_dismissal_request)
        true
      end

      # EMU "Outside collaborators" are presented as "Repository collaborators" to customers
      sig { params(actor: T.nilable(T.any(Business, Organization, User))).returns(String) }
      def outside_collaborators_verbiage(actor)
        business = if actor&.is_a?(Business)
          actor
        elsif actor&.is_a?(Organization)
          actor.business
        elsif actor&.is_a?(User)
          actor.business
        else
          nil
        end

        return "repository collaborators" if business&.emu_repository_collaborators_enabled?

        GitHub.outside_collaborators_flavor
      end

      sig { returns(T::Hash[Symbol, T::Boolean]) }
      memoize def permission_grants
        navigation_permissions = [
          :read_enterprise_audit_logs,
          :read_enterprise_custom_org_role,
          :read_enterprise_custom_enterprise_role,
          :read_enterprise_sso,
        ]

        return navigation_permissions.each_with_object({}) do |permission, grants|
          grants[permission] = false
        end unless user && business

        Authz.domain.check_multiple_permissions(T.must(user), navigation_permissions, T.must(business))
      end

    end
  end
end
