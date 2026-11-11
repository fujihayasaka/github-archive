# typed: true
# frozen_string_literal: true

class RepositoryNetworkGraphBuilderJob < ApplicationJob
  queue_as :netgraph
  locked_by timeout: 1.hour, key: -> (job) { job.arguments[0][:repository_network_graph_id] }
  retry_on_dirty_exit

  retry_on ActiveRecord::RecordNotFound, JobStatus::NotFound, wait: :polynomially_longer, attempts: 5 # will retry 4 times over 6 minutes

  def self.prefix
    name
  end

  def perform(repository_network_graph_id:)
    network_graph = Repository::NetworkGraph.find(repository_network_graph_id)
    push_failbot_context(network_graph)

    job_status = Repositories::JobStatus.find!(network_graph.job_status_id_with_prefix)
    # While we are transitioning to the new job status, we may have some old job statuses that are not prefixed.
    # If we can't find the job status with the prefix, try to find the job status without the prefix.
    job_status = Repositories::JobStatus.find!(network_graph.job_status_id) if job_status.nil?
    job_status.track do
      with_write { network_graph.build! }
    end
  end

  private

  def push_failbot_context(network_graph)
    repo_id = network_graph.repository&.id

    Failbot.push(
      "gh.repo.id": repo_id,
      "gh.job_status.id": network_graph.job_status_id_with_prefix,
    )
  end
end
