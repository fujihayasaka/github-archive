# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class UserSignupFollowupJob < ApplicationJob
  queue_as :user_signup_followup

  # Only a single unique instance of the job can be concurrently running
  # per verification banner being triggered
  locked_by timeout: 1.hour, key: -> (job) { "user_signup_followup::#{job.arguments[0]}" }

  # Sends a reminder email to verify account after user creation
  # user          - The GlobalID of the user that was created.
  #
  # Returns nothing.

  def perform(user)
    return unless user
    kv_key = "user_id.#{user.id}.user_signup_followup_job"

    if Users::Kv.store.exists(kv_key).value!
      nil
    else
      with_write do
        Users::Kv.store.set(kv_key, "true", expires: 2.days.from_now)
        ApplicationRecord::Domain::KeyValues.throttle do
          user.send_email_verification_reminder
        end
      end
    end
  end
end
