# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class UpdateUserHiddenMismatchesJob < ApplicationJob
  # Don't schedule this job when spammy checks aren't enabled.
  schedule interval: 5.minutes, condition: -> { GitHub.spamminess_check_enabled? }

  queue_as :spam

  retry_on_dirty_exit

  UPDATED_SINCE_TIME_SPAN = 30.minutes

  # Public: Perform the job to update the `*.user_hidden` column from `users.spammy`.
  #
  # Returns nothing.
  def perform
    user_ids = Spam::UpdateUserHidden.user_ids_for_mismatches(
      updated_since: UPDATED_SINCE_TIME_SPAN.ago,
    )

    user_ids.each do |user_id|
      UpdateTableUserHiddenJob.perform_later(user_id, Spam::Spammable.tables_classes_including.keys)
    end
  end
end
