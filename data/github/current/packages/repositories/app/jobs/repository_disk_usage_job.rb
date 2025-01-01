# typed: true
# frozen_string_literal: true

class RepositoryDiskUsageJob < ApplicationJob
  queue_as :repository_disk_usage
  retry_on_dirty_exit

  resolve_tenant_context do |repository_id|
    Repositories::Public.resolve_tenant(id: repository_id)
  end

  def perform(repository_id)
    repository = Repository.find_by(id: repository_id)
    return unless repository
    Failbot.push("gh.repo.id": repository.id)
    repository.update_disk_usage
  rescue GitRPC::Protocol::DGit::ResponseError => e
    GitHub.logger.error(
      :exception => e,
      "code.namespace" => self.class.name,
      "code.function" => __method__,
      "gh.repo.id" => repository&.id
    )

    nil
  end
end
