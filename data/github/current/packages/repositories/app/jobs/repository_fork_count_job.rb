# typed: true
# frozen_string_literal: true

class RepositoryForkCountJob < ApplicationJob
  queue_as :repository_fork_count
  retry_on_dirty_exit

  resolve_tenant_context do |repository_id|
    Repositories::Public.resolve_tenant(id: repository_id)
  end

  def perform(repository_id)
    repository = T.cast(Repositories.domain.by_id(repository_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
    return unless repository
    Failbot.push("gh.repo.id": repository.id)
    with_write do
      repository.calculate_network_counts!
    end
  end
end
