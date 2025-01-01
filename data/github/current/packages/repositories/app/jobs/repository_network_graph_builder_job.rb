# typed: true
# frozen_string_literal: true

class RepositoryNetworkGraphBuilderJob < ApplicationJob
  default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

  queue_as :netgraph
  locked_by timeout: 1.hour, key: -> (job) { job.arguments[0][:repository_network_graph_id] }
  retry_on_dirty_exit

  retry_on ActiveRecord::RecordNotFound, JobStatus::NotFound, wait: :polynomially_longer, attempts: 5 # will retry 4 times over 6 minutes

  def perform(repository_network_graph_id:)
    network_graph = Repository::NetworkGraph.find(repository_network_graph_id)
    push_failbot_context(network_graph)

    job_status = JobStatus.find!(network_graph.job_status_id)
    job_status.track do
      network_graph.build!
    end
  end

  private

  def push_failbot_context(network_graph)
    repo_id = network_graph.repository&.id

    Failbot.push(
      "gh.repo.id": repo_id,
      "gh.job_status.id": network_graph.job_status_id,
    )
  end
end
