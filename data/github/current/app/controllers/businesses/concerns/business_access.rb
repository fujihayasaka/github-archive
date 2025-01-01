# typed: true
# frozen_string_literal: true

module Businesses::Concerns::BusinessAccess
  include GitHub::Memoizer
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { ApplicationController }

  included do
    T.bind(self, T.class_of(ApplicationController))

    memoize def this_business
      if GitHub.single_business_environment? && !slug_param
        GitHub.global_business
      else
        Business.find_by(slug: slug_param)
      end
    end
    helper_method :this_business

    def slug_param
      params[:slug]
    end

    # `allow_members` is used to indicate that when checking the current user's access,
    # members should be considered as having access.
    def business_access_required(allow_members: false, allow_unaffiliated: false, allow_org_owners: false)
      return render_404 unless this_business

      if business_access?(allow_members: allow_members, allow_unaffiliated: allow_unaffiliated, allow_org_owners: allow_org_owners)
        nil
      elsif this_business.pending_admin_invitation_for(current_user, role: Business::OWNER_ROLE)
        redirect_to enterprise_owner_invitation_path(this_business)
      elsif this_business.pending_admin_invitation_for(current_user, role: Business::BILLING_MANAGER_ROLE)
        redirect_to enterprise_billing_manager_invitation_path(this_business)
      elsif this_business.enterprise_managed_user_enabled? && this_business.sso_redirect_enabled? && (!logged_in? || !current_user.is_enterprise_managed? || this_business != current_user.enterprise_managed_business)
        redirect_to business_idm_sso_enterprise_path(this_business)
      else
        render_404
      end
    end

    def redirect_if_pending_enterprise_admin_invitation_or_sso
      return render_404 unless this_business
      if this_business.pending_admin_invitation_for(current_user, role: Business::OWNER_ROLE)
        redirect_to enterprise_owner_invitation_path(this_business)
      elsif this_business.pending_admin_invitation_for(current_user, role: Business::BILLING_MANAGER_ROLE)
        redirect_to enterprise_billing_manager_invitation_path(this_business)
      elsif this_business.enterprise_managed_user_enabled? && this_business.sso_redirect_enabled? && (!logged_in? || !current_user.is_enterprise_managed? || this_business != current_user.enterprise_managed_business)
        redirect_to business_idm_sso_enterprise_path(this_business)
      end
    end

    # `allow_members` is used to indicate that when checking the current user's access,
    # members should be considered as having access.

    # allow_org_owners is used to allow org owners for vnext enabled businesses to have certain enterprise permissions
    # related to repo level budgets
    def business_access?(allow_members: false, allow_unaffiliated: false, allow_org_owners: false)
      this_business&.owner?(current_user) ||
        this_business&.billing_manager?(current_user) ||
        has_member_business_access?(allow_members: allow_members, allow_unaffiliated: allow_unaffiliated) ||
        has_org_admin_access?(allow_org_owners: allow_org_owners)
    end

    # Does the current user have restricted access to the enterprise account
    # because they are a member of an org within the enterprise?
    #
    # Note: Only returns true for a member if `allow_members` is set to true.
    #
    # Returns Boolean.
    def has_member_business_access?(allow_members: false, allow_unaffiliated: false)
      return false if this_business.nil? || !logged_in?

      return true if allow_unaffiliated && this_business.supports_unaffiliated_user_accounts? && this_business.exclusive_unaffiliated_member?(current_user)

      # Enterprise members can only GET /enterprises/:slug
      if allow_members
        # Permit all installations members in GHES
        return true if GitHub.single_business_environment?

        if current_user.is_enterprise_managed?
          return current_user.business_user_accounts.first.business_id == this_business.id
        end

        # Permit members of orgs owned by the enterprise on dotcom
        return this_business.user_is_member_of_owned_org?(current_user)
      end

      false
    end

    def has_org_admin_access?(allow_org_owners: false)
      return false if this_business.nil? || !logged_in?
      return false unless allow_org_owners

      this_business.user_is_owner_of_owned_org?(current_user)
    end
  end
end
