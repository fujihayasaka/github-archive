# typed: true
# frozen_string_literal: true

# Public: Responsible for handling the creation, removal,
# and upload of our email suppression list to internal and
# external services like MailChimp.
module SuppressionList

  # Public: Does a user have any email addresses included
  # in the suppression list?
  #
  # Returns a Boolean.
  def self.includes_user?(user)
    return false unless user
    user.email_roles.suppressed.exists?
  end

  # Public: Add a user to the suppression list.
  # - Marks all of a user's email addresses as suppressed in GitHub.
  # - Unsubscribes the user's email addresses in Campaign Monitor.
  def self.add_user(user)
    return unless user
    emails = user.emails
    emails.map(&:mark_as_suppressed!)
  end

  # Public: Remove a user from the suppression list.
  def self.remove_user(user)
    return unless user
    user.email_roles.suppressed.delete_all
  end

end
