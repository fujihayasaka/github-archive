# typed: true
# frozen_string_literal: true

class RemoveFromSuppressionListJob < ApplicationJob
  queue_as  :remove_from_suppression_list

  # Remove the user from the suppression list.
  #
  # - Resubscribe them to the MailChimp list, as being
  # removed from the suppression list means the user
  # is eligible again to receive marketing material.
  #
  # user_id - The integer user id.
  #
  # Returns nothing.
  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user
    Failbot.push(user: user.login)

    GitHub.dogstats.time "suppression_list", tags: ["action:remove_user", "via:job"] do
      with_write { SuppressionList.remove_user(user) }
    end

    email = user.primary_user_email
    MailchimpSubscribeJob.perform_later(T.must(email).id) if GitHub.mailchimp_enabled?
  end
end
