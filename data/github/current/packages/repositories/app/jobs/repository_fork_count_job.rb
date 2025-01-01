# typed: true
# frozen_string_literal: true

class RepositoryForkCountJob < ApplicationJob
  queue_as :repository_fork_count
  retry_on_dirty_exit

  resolve_tenant_context do |repository_id|
    Repositories::Public.resolve_tenant(id: repository_id)
  end

  def perform(repository_id)
    return unless GitHub.flipper[:repo_fork_count_job].enabled?

    repository = Repository.find_by(id: repository_id)
    return unless repository
    Failbot.push("gh.repo.id": repository.id)
    with_write do
      repository.calculate_network_counts!
    end
  end
end
