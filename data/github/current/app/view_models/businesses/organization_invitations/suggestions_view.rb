# typed: true
# frozen_string_literal: true

class Businesses::OrganizationInvitations::SuggestionsView < AutocompleteView

  # Public: The suggested organizations for the query.
  def suggested_organizations
    suggestions.map do |org|
      [org, SuggestedOrganization.new(business, org, current_user)]
    end
  end

  # Public: Can business admins invite orgs by email? No.
  #
  # Note: Overrides the logic in AutoCompleteQuery#allow_email_invites?
  #
  # Returns a Boolean
  def allow_email_invites?
    false
  end

  class SuggestedOrganization
    def initialize(business, org, inviter)
      @business = business
      @invitation = BusinessOrganizationInvitation.new \
        business: business, inviter: inviter, invitee: org
      @valid = @invitation.valid?
    end

    attr_accessor :business, :invitation, :valid

    # Public: Should the suggestion item for the specified org be enabled?
    #
    # Returns a Boolean.
    alias_method :item_enabled?, :valid

    # Public: Can the specified org be invited to the business?
    #
    # Returns a Boolean.
    alias_method :invitable?, :valid

    # Public: Get text explaining why the org cannot be invited
    #
    # Returns a String (empty if the org *is* invitable).
    def uninvitable_reason_text
      if !invitable?
        invitation.errors.full_messages.first
      else
        ""
      end
    end
  end
end
