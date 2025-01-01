# typed: true
# frozen_string_literal: true

class BillingManagers::InviteeSuggestionsView < AutocompleteView

  # Public: Returns a list of suggested users for billing manager
  # while skipping users that are trade restricted.
  #
  # Returns an Array
  def suggestions
    users = super
    @invitee_suggestions ||= users.reject(&:has_any_trade_restrictions?)
  end

  # Public: Can the specified user be invited to the organization?
  #
  # user - User to check invitability of.
  #
  # Returns a boolean.
  def invitable?(user)
    valid = Organization::InviteStatus.new(organization, user, inviter: current_user, role: :billing_manager).valid?
    valid && !organization.pending_invitation_for(user, role: :billing_manager)
  end

  # Public: Should the suggestion item for the specified user be enabled?
  #
  # Returns a boolean.
  def item_enabled_for?(user)
    invitable?(user)
  end

  # Public: Get the CSS octicon classes to use in the suggestion item for the
  # specified user.
  #
  # user - User to get octicon classes for.
  #
  # Returns a string.
  def octicon_classes_for(user)
    (invitable?(user) ? "plus" : "check")
  end

  # Public: Get text explaining why the specified user cannot be invited
  # as a billing manager
  #
  # user - User to get text for.
  #
  # Returns a string (empty if the user *is* invitable).
  def uninvitable_reason_text_for(user)
    if organization.billing.manager?(user)
      "Already a billing manager in this organization"
    elsif organization.pending_invitation_for(user, role: :billing_manager)
      "Already invited to be a billing manager in this organization"
    else
      ""
    end
  end
end
