# typed: true
# rubocop:disable Primer/PrimerOcticon
# frozen_string_literal: true

class Orgs::Invitations::InviteeSuggestionsView < AutocompleteView
  # this pattern is similar to User::EMAIL_REGEX but is modified to find any and all valid email addresses in the query
  BULK_EMAIL_PATTERN = /([^@\s.\0][^@\s\0]*@\[?[a-z0-9.-]+\]?)[,\s]?/i

  # Override the query method from AutocompleteView
  # to handle queries that start with "@" for username handles.
  # This allows users to be searched by their full handle (e.g., "@username").
  def query
    original_query = super # Get the query from AutocompleteView's implementation

    if original_query.is_a?(String) && original_query.start_with?("@")
      # Ensure there are characters after the initial '@'
      substring_after_at = original_query.delete_prefix("@")
      if substring_after_at.present? && !substring_after_at.include?("@")
        return substring_after_at # Strip the leading "@"
      end
    end

    original_query # Return original query if no stripping is needed
  end

  def suggested_invitees
    suggestions.map do |user|
      [user, SuggestedInvitee.new(organization, user, current_user, emu_admin_id == user.id)]
    end
  end

  def email_addresses
    @email_addresses ||= query.scan(BULK_EMAIL_PATTERN).flatten.uniq
  end

  # Overrides `AutocompleteView#org_members_only?` to include check for org
  # belongs to a business and has no seats remaining to scope results to
  # business members
  def org_members_only?
    org_members_only || business_members_only?
  end

  def business_members_only?
    return false if GitHub.single_business_environment?
    return false unless organization.business.present?

    organization.available_invitable_seats.zero?
  end

  def email_match?(user)
    email_query? && user.profile.email == query
  end

  def emu_admin_id
    @emu_admin_id ||= organization.business&.enterprise_managed_user_enabled? && organization.business.user_accounts.roles(:emu_admin).pluck(:user_id).first || 0
  end

  class SuggestedInvitee
    include OcticonsHelper

    def initialize(organization, user, inviter, uninvitable = false)
      @user_direct_or_team_member = organization.direct_or_team_member?(user)
      @blocked_from_org = organization.blocking?(user)
      @blocked_warning = inviter.blocking?(user)
      @valid = Organization::InviteStatus.new(organization, user, inviter: inviter).valid?

      if uninvitable
        @valid = false
        @uninvitable = true
      end

      # bypass_org_invites_enabled? currently is aliased to enterprise?
      # On enterprise there are no org invites and instead org admins directly
      # add users to the org
      if GitHub.bypass_org_invites_enabled?
        @two_factor_not_enabled_error = !organization.two_factor_requirement_met_by?(user)
        @valid = @valid && !@two_factor_not_enabled_error
      end
    end

    attr_accessor :valid, :two_factor_not_enabled_error, :user_direct_or_team_member, :blocked_from_org, :blocked_warning, :uninvitable

    # Public: Should the suggestion item for the specified user be enabled?
    #
    # Returns a boolean.
    alias_method :item_enabled?, :valid

    # Public: Can the specified user be invited to the organization?
    #
    # Returns a boolean.
    alias_method :invitable?, :valid

    # Public: Does the user meet the organization's two factor auth requirement?
    #
    # Returns a boolean.
    alias_method :two_factor_not_enabled_error?, :two_factor_not_enabled_error

    # Public: Is the user a direct or team member of the organization?
    #
    # Returns a boolean.
    alias_method :user_direct_or_team_member?, :user_direct_or_team_member

    # Public: Is the invitee blocked by the organization
    #
    # Returns a boolean.
    alias_method :blocked_from_org?, :blocked_from_org

    # Public: Is the invitee blocked by the inviter of the organization
    #
    # Returns a boolean.
    alias_method :blocked_warning?, :blocked_warning

    # Public: Get text explaining why the user cannot be invited
    #
    # Returns a string (empty if the user *is* invitable).
    def uninvitable_reason_text
      case
      when user_direct_or_team_member?
        "Already in this organization"
      when two_factor_not_enabled_error?
        "User needs to enable two-factor authentication"
      when blocked_from_org?
        "This user is blocked by the organization"
      when uninvitable
        "The user can not become a member of this organization"
      else
        ""
      end
    end

    # Public: Get the text explaining what a user will be warned about before inviting
    #
    # Returns a string or nil if there is not a reason
    def warning_reason_text
      case
      when blocked_warning?
        "You have blocked this user. Proceed anyway?"
      else
        nil
      end
    end
  end
end
