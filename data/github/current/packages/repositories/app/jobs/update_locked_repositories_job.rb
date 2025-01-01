# typed: true
# frozen_string_literal: true

class UpdateLockedRepositoriesJob < ApplicationJob
  default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

  queue_as :critical
  retry_on_dirty_exit

  def perform(user_id)
    GitHub.dogstats.increment "update_locked_repositories"
    GitHub.logger.info(
      "Update locked repositories",
      "code.namespace" => self.class.name,
      "code.function" => __method__,
      "gh.user.id" => user_id
    )
    if user = User.where(id: user_id).first
      user.update_locked_repositories
    end
  end
end
