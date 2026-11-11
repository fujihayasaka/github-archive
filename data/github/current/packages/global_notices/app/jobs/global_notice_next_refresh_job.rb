# typed: true
# frozen_string_literal: true

class GlobalNoticeNextRefreshJob < ApplicationJob
  queue_as :global_notice_next_refresh

  retry_on_dirty_exit

  # We only want to run one of these jobs at a time per user
  locked_by timeout: 5.minutes, key: ->(job) { job.arguments[0] }

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user

    lock(user_id) do
      GlobalNotice.throttle_writes do
        user.global_notice.refresh
      end
    end
  end

  private

  # Internal: Use a GitHub::Restraint to prevent simultaneous updates
  #
  # business_id - ID of the business we want to lock
  # block       - The code block to execute with an exclusive lock
  #
  # Returns nothing
  def lock(user_id, &block)
    lock_key = "global-notice-next-refresh-for-#{user_id}"

    restraint.lock!(lock_key, _max_concurrency = 1, _ttl = 5.minutes, &block)
  end

  # Internal: The restraint for locking and preventing simultaneous updates
  #
  # Returns GitHub::Restraint
  def restraint
    @restraint ||= GitHub::Restraint.new
  end
end
