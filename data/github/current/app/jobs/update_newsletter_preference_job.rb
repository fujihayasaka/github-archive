# typed: false
# frozen_string_literal: true

class UpdateNewsletterPreferenceJob < ApplicationJob
  queue_as :user_signup
  retry_on_dirty_exit

  # Public: Update a user's newsletter settings
  #
  # user_id - the User id
  # preference - "transactional" or "marketing"
  # signup - a Boolean. Whether or not the preference is being set as part of the signup process
  #
  def perform(user_id, preference, signup = false)
    return unless user = User.find_by_id(user_id)

    with_write do
      if preference == "marketing"
        NewsletterPreference.set_to_marketing(user: user, source: "job", signup: signup)
      else
        NewsletterPreference.set_to_transactional(user: user, source: "job")
      end
    end
  end
end
