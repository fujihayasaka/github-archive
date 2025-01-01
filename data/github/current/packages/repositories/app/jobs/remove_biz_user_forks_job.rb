# typed: true
# frozen_string_literal: true

class RemoveBizUserForksJob < ApplicationJob
  queue_as :remove_biz_user_forks

  retry_on_dirty_exit

  def perform(biz_id:, belonging_to_user_id:)
    start = Time.current

    @biz = Business.find(biz_id)
    @user = User.find(belonging_to_user_id)

    biz_internal_forks.find_in_batches do |batch|
      inaccessible = repos_with_inaccessible_root(batch)
      inaccessible.each do |user_fork|
        with_write { user_fork.throttle { user_fork.remove(user_fork.owner, send_email: true) } }
      end
    end
  ensure
    GitHub.dogstats.timing_since("job.remove_biz_user_forks.time", start)
  end

  private

  def biz_internal_forks
    @biz_internal_forks ||= Repository.biz_internal_forks_for(business: @biz, belonging_to_user: @user)
  end

  def repos_with_inaccessible_root(batch)
    batch.reject do |repo|
      next true unless repo.active? # Reject it, preventing removal, if it's not active.
      next true unless repo.network&.root # Reject it, preventing removal, if there's a bad network.
      repo.network.root.pullable_by_user_or_no_plan_owner?(@user)
    end
  end
end
