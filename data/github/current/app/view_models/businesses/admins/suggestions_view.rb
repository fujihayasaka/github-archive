# typed: true
# frozen_string_literal: true

class Businesses::Admins::SuggestionsView < AutocompleteView
  attr_reader :stafftools_invite

  # Public: The suggested admins for the query.
  def suggested_admins
    suggestions.map do |user|
      [user, SuggestedAdmin.new(business, user, current_user, bypass_admin_invite?, stafftools_invite)]
    end
  end

  def email_match?(user)
    email_query? && user.profile.email == query
  end

  # Public: Can the current user invite non GitHub users as business admins
  # via email?
  #
  # Note: Overrides the logic in AutoCompleteQuery#allow_email_invites?
  #
  # Returns a Boolean
  def allow_email_invites?
    !GitHub.bypass_business_member_invites_enabled?
  end

  def bypass_admin_invite?
    stafftools_invite || GitHub.bypass_business_member_invites_enabled?
  end

  class SuggestedAdmin
    def initialize(business, user, inviter, bypass_admin_invite, stafftools_invite)
      @user_is_business_admin = business.owner?(user) || business.billing_manager?(user)
      valid_owner_invitation = Business::MemberInviteStatus.new(
        business, user, inviter: inviter, role: :owner,
        stafftools_invite: stafftools_invite).valid?
      valid_billing_manger_invitation = Business::MemberInviteStatus.new(
        business, user, inviter: inviter, role: :billing_manager,
        stafftools_invite: stafftools_invite).valid?

      @valid = valid_owner_invitation && valid_billing_manger_invitation

      # In the Enterprise environment, admins can be added directly to the
      # global business. Ensure that the two-factor requirement of the business
      # is respected.
      # Invitation flow is also bypassed when adding an owner directly via
      # stafftools on dotcom - ensure 2fa compatibility for that case as well
      if bypass_admin_invite
        @two_factor_not_enabled_error = business.two_factor_requirement_enabled? &&
          !user.two_factor_authentication_enabled?
        @valid = @valid && !@two_factor_not_enabled_error
      end
    end

    attr_accessor :user_is_business_admin, :valid, :two_factor_not_enabled_error

    # Public: Should the suggestion item for the specified user be enabled?
    #
    # Returns a Boolean.
    alias_method :item_enabled?, :valid

    # Public: Can the specified user be invited as a business admin?
    #
    # Returns a boolean.
    alias_method :invitable?, :valid

    # Public: Does the user meet the business two-factor requirement?
    #
    # Returns a Boolean.
    alias_method :two_factor_not_enabled_error?, :two_factor_not_enabled_error

    # Public: Is the user already an admin of the business?
    #
    # Returns a boolean.
    alias_method :user_is_business_admin?, :user_is_business_admin

    # Public: Get text explaining why the user cannot be invited
    #
    # Returns a string (empty if the user *is* invitable).
    def uninvitable_reason_text
      case
      when user_is_business_admin?
        "Already an enterprise administrator"
      when two_factor_not_enabled_error?
        "User needs to enable two-factor authentication"
      else
        ""
      end
    end
  end
end
