# typed: strict
# frozen_string_literal: true

class Users::Cache::InvalidationJob < ApplicationJob
  queue_as :users_cache_invalidation
  retry_on_dirty_exit

  sig { params(id: Integer, event: T.nilable(String)).void }
  def perform(id, event = nil)
    Users::Cache::UserByIdClient.new(id).invalidate(event)
    GitHub.logger.info("Users::Cache::InvalidationJob: Invalidated cache for id: #{id}, event: #{event}")
  end
end
