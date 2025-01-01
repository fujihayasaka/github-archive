# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class UserSignupConfirmationJob < ApplicationJob
  # Sends a one-time signup confirmation email to users that
  # have elected a transactional email preference.
  #
  # This job is queued after a user verifies their email address.
  queue_as :user_signup

  def perform(email_id)
    email = UserEmail.find_by(id: email_id)
    user  = email.try(:user)

    Failbot.push(
      job: self.class.name,
      user_id: user.try(:id),
      email_id: email_id,
    )
    return unless email && user

    if should_receive_welcome_email?(user)
      AccountMailer.welcome(email).deliver_now
      with_write { Onboarding.for(user).welcomed_via_email! }
    end
  end

  private

  # Private: Should the user receive the welcome email?
  # Returns a Boolean.
  def should_receive_welcome_email?(user)
    return false if NewsletterPreference.marketing?(user: user)
    recent_signup?(user) && !already_welcomed?(user)
  end

  # Private: Whether or not a user already received the welcome email or series.
  # Returns a Boolean.
  def already_welcomed?(user)
    onboarding = Onboarding.for(user)
    onboarding.welcomed_via_email? || onboarding.enrolled_in_welcome_series?
  end

  # Private: Did the user sign up recently?
  # Returns a Boolean.
  def recent_signup?(user)
    user.created_at > 30.days.ago
  end
end
