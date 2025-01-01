# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: false
# frozen_string_literal: true

class UserSignupJob < ApplicationJob
  queue_as :user_signup

  def perform(user_id, invitation_token: nil, repo_invitation_token: nil)
    Failbot.push(user_id: user_id)
    user = User.find_by_id(user_id)
    return unless user
    Failbot.push(user_id: user&.id)

    with_write { user.send_email_verification(invitation_token: invitation_token, repo_invitation_token: repo_invitation_token) }

    email_verification_in_millseconds = (Time.now - user.created_at) * 1_000
    GitHub.dogstats.distribution("user.signup.email.verification.time", email_verification_in_millseconds)
    with_write { user.onboard_to_billing }
  end
end
