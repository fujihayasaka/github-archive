# typed: true
# frozen_string_literal: true

# This is a temporary stopgap to allow broadcast alerts to repositories with a vulnerable dependency
#  that is defined in a snapshot.
# It runs as a background job near the beginning of VulnerableVersionRangeCreateVulnerabilityAlertsJob.
# It retrieves a list of repository IDs that have a vulnerable dependency defined in a snapshot, and kicks off
#   UpdateRepositoryVulnerabilityAlerts for those repositories, triggering a new alert.
# In the long term, this job will be removed in favor of deeper integration of snapshot data in the existing
#   dependency-graph-api GraphQL API.
class ReprocessRepositoryAlertsWithSnapshotDependencyJob < ApplicationJob
  queue_as :repository_dependencies

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def vulnerable_repository_ids(vulnerable_version_range)
    client = DependencyGraph::RepositoryDependenciesClient.new(request_timeout_seconds: 120)
    client.get_repositories_containing_vvr(vulnerable_version_range: vulnerable_version_range)
  end

  def perform(vulnerable_version_range)
    all_repository_ids = vulnerable_repository_ids(vulnerable_version_range).uniq
    GitHub.dogstats.distribution("dependency_graph.reprocess_repository_alerts_with_snapshot_dependency_job.ids_to_process", all_repository_ids.count)
    all_repository_ids.each do |repository_id|
      repository = Repositories::Public.find_active(repository_id)
      next if repository.nil?
      # We're using a reason here that is not semantically accurate, but it has the right behavior and this code is temporary.
      UpdateRepositoryVulnerabilityAlertsJob.enqueue_for_repository(repository, reason: :on_dependency_snapshot)
    end
  end
end
