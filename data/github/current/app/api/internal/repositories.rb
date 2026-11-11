# typed: true
# frozen_string_literal: true

class Api::Internal::Repositories < Api::Internal
  # Internal: Perform an audit of repository state. For each provided repo id, returns the repo id and result of audit,
  # indicating if the repo is active, inactive, archived, or not_found.
  # These audits are performed by the git backend to look for orphaned git data that can be purged.
  post "/internal/repositories/audits", operation_id: :internal, exempt_from_tenant_context_requirement: true, read_from_replicas: true do
    @route_owner = "@github/repos"

    data = receive_with_schema("repository-audit", "create")
    ids = Set.new(data["repository_ids"])
    results = []

    Repository.where(id: ids).pluck(:id, :active).each do |repo_id, active|
      status = active ? "active" : "inactive"
      results << audit_result(repo_id, status)
      ids.delete(repo_id)
    end

    ids.each do |id|
      GitHub.logger.info(
        "Repository not found",
        "code.namespace" => "Api::Internal::Repositories",
        "code.function" => "repository.audit.not_found",
        "gh.repo.id" => id
      )
      results << audit_result(id, "not_found")
    end

    results.each do |value|
      result = value[:result]
      GitHub.dogstats.increment("repository.audit", tags: ["result:#{result}"])
    end

    audit = { results: results }
    deliver_raw audit, status: 200
  end

  # Internal: Given a repo identifier, returns the repo id, network id and nwo.
  get "/internal/repositories/:repository_id", operation_id: :internal do
    @route_owner = "@github/repos"
    repo = if params[:include_hidden] == "true"
      find_repo_include_hidden!
    else
      find_repo!
    end

    deliver :internal_repository_hash, repo
  end

  # Internal: Given a list of network ids, return the network id and it's status (new, active, empty, not_found)
  post "/internal/networks/audits", operation_id: :internal, exempt_from_tenant_context_requirement: true, read_from_replicas: true do
    @route_owner = "@github/repos"

    data = receive_with_schema("network-audit", "create")
    network_ids = Set.new(data["network_ids"])
    results = []

    network_ids.each do |network_id|
      network = RepositoryNetwork.find_by(id: network_id)
      status =
        if network.nil?
          "not_found"
        else
          count = network.active_and_deleted_repositories.count
          if count > 0
            "active"
          elsif T.must(network.updated_at) > 1.hour.ago
            "new"
          else
            "empty"
          end
        end

      results << { network_id: network_id, status: status }
    end

    audit = { results: results }
    deliver_raw audit, status: 200
  end

  # delete an empty network
  delete "/internal/networks/:network_id", operation_id: :internal do
    @route_owner = "@github/repos"
    network_id = params[:network_id]

    network = RepositoryNetwork.find_by(id: network_id)
    deliver_error!(404, message: "Network not found") if network.nil?

    network = T.must(network)
    count = network.active_and_deleted_repositories.count
    timestamp = T.must(network.updated_at)

    if timestamp < 1.hour.ago && count == 0
      GitHub.logger.info("Deleting empty network", network_id: network_id)
      network.destroy!
      deliver_empty(status: 204)
    else
      # return 405 NOT ALLOWED if the network is not empty or too new
      GitHub.logger.info("Not deleting network", network_id: network_id, count: count, timestamp: timestamp)
      deliver_empty(status: 405)
    end
  end

  # Internal: Behaves like find_repo! but returns disabled/spammy repos.
  def find_repo_include_hidden!
    repo = find_repo
    repo&.network_broken?
    record_or_404(repo)
  rescue Repository::NetworkDependency::NetworkMissingError => e
    Failbot.report e
    deliver_disabled_repo_error!(repo)
  end

  def externally_accessible?
    false
  end

  def require_request_hmac?
    true
  end

  def authenticated_for_private_mode?
    true
  end

  # Relax user-agent requirements for internal API endpoints used by babeld
  def user_agent_allows_access_to_garage_hosts?
    request.user_agent =~ /#{GitHub.current_sha}|^babeld\/.*/
  end

  # An individual audit result
  def audit_result(id, result)
    {
      repository_id: id,
      result: result
    }
  end
end
