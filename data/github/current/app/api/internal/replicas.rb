# typed: true
# frozen_string_literal: true

class Api::Internal::Replicas < Api::Internal
  ERROR_REPLICA_EXISTS = "Replica exists on host."
  ERROR_INVALID_ENTITY_SPEC = "Invalid spokes entity spec."
  ERROR_REPLICA_NOT_FOUND = "No replica on host."
  ERROR_HOST_TOO_BUSY = "Host is too busy."

  post "/internal/spokes/entities/:entity_type/:entity_id/replicas", operation_id: :internal, resolve_tenant_context: :resolve_tenant_from_entity do
    @route_owner = "@github/repos"

    data = receive(Hash)
    type, id = entity_from_params
    host = data["host"]

    case type
    when "gist"
      if GitHub::DGit::Routing.all_hosts_for_gist(id).include?(host)
        deliver_error!(409, message: ERROR_REPLICA_EXISTS)
      end
      ctx = GitHub::DGit::Maintenance::GistMaintenanceContext.new
    when "network"
      if GitHub::DGit::Routing.all_hosts_for_network(id).include?(host)
        deliver_error!(409, message: ERROR_REPLICA_EXISTS)
      end
      ctx = GitHub::DGit::Maintenance::NetworkMaintenanceContext.new
    else
      deliver_error!(422, message: ERROR_INVALID_ENTITY_SPEC)
    end

    unless ctx.ok_to_queue_job?(host)
      deliver_error!(429, message: ERROR_HOST_TOO_BUSY)
    end

    ctx.enqueue_create_replica(id, data["host"])
    deliver_raw({ status: "replica creation scheduled for #{type}/#{id}" }, status: 202)
  end

  post "/internal/spokes/entities/:entity_type/:entity_id/replicas/:host/repair", operation_id: :internal, resolve_tenant_context: :resolve_tenant_from_repair_entity do
    @route_owner = "@github/repos"

    type, id, _ = repair_entity_from_params
    host = params["host"]

    # We only need a context for ok_to_queue_job? It would seem like the base
    # MaintenanceContext would be fine but the metrics it generates requires an
    # "entity". That "entity" will be network for everything besides gists.
    case type
    when "gist"
      ctx = GitHub::DGit::Maintenance::GistMaintenanceContext.new
    else
      ctx = GitHub::DGit::Maintenance::NetworkMaintenanceContext.new
    end

    deliver_error!(429, message: ERROR_HOST_TOO_BUSY) unless ctx.ok_to_queue_job?(host, increment: true)

    case type
    when "gist"
      GitHub::DGit::Maintenance.repair_gist_replica(id, host)
    when "repo"
      deliver_error!(404) # no longer supported
    when "wiki"
      deliver_error!(404) # no longer supported
    when "network"
      GitHub::DGit::Maintenance.repair_network_replica(id, host)
    else
      deliver_error!(422, message: ERROR_INVALID_ENTITY_SPEC)
    end

    deliver_raw({ status: "replica repair scheduled for #{type} #{id}" }, status: 200)
  end

  post "/internal/spokes/entities/:entity_type/:entity_id/replicas/repair-doa", operation_id: :internal, resolve_tenant_context: :resolve_tenant_from_repair_entity do
    @route_owner = "@github/repos"

    type, id, _ = repair_entity_from_params

    case type
    when "repo"
      SpokesRepairDoaRepoJob.perform_later(id)
    when "wiki"
      SpokesRepairDoaRepoJob.perform_later(id, true)
    else
      deliver_error!(422, message: ERROR_INVALID_ENTITY_SPEC)
    end

    deliver_raw({ status: "replica DOA repair scheduled for #{type} #{id}" }, status: 200)
  end

  patch "/internal/spokes/entities/:entity_type/:entity_id/replicas/:src_host", operation_id: :internal, resolve_tenant_context: :resolve_tenant_from_entity do
    @route_owner = "@github/repos"

    type, id = entity_from_params
    src_host = params["src_host"]

    data = receive(Hash)
    dst_host = data["dst_host"]

    existing_hosts = []
    case type
    when "gist"
      existing_hosts = GitHub::DGit::Routing.all_hosts_for_gist(id)
      ctx = GitHub::DGit::Maintenance::GistMaintenanceContext.new
    when "network"
      existing_hosts = GitHub::DGit::Routing.all_hosts_for_network(id)
      ctx = GitHub::DGit::Maintenance::NetworkMaintenanceContext.new
    else
      deliver_error!(422, message: ERROR_INVALID_ENTITY_SPEC)
    end

    unless existing_hosts.include?(src_host)
      deliver_error!(404, message: ERROR_REPLICA_NOT_FOUND)
    end
    if existing_hosts.include?(dst_host)
      deliver_error!(409, message: ERROR_REPLICA_EXISTS)
    end

    unless ctx.ok_to_queue_job?(src_host) || ctx.ok_to_queue_job?(dst_host)
      deliver_error!(429, message: ERROR_HOST_TOO_BUSY)
    end

    ctx.enqueue_move_replica(id, src_host, dst_host)
    deliver_raw({ status: "replica move scheduled for #{type}/#{id}" }, status: 202)
  end

  delete "/internal/spokes/entities/:entity_type/:entity_id/replicas/:host", operation_id: :internal, resolve_tenant_context: :resolve_tenant_from_entity do
    @route_owner = "@github/repos"

    type, id = entity_from_params
    host = params["host"]

    existing_hosts = []
    case type
    when "gist"
      existing_hosts = GitHub::DGit::Routing.all_hosts_for_gist(id)
      ctx = GitHub::DGit::Maintenance::GistMaintenanceContext.new
    when "network"
      existing_hosts = GitHub::DGit::Routing.all_hosts_for_network(id)
      ctx = GitHub::DGit::Maintenance::NetworkMaintenanceContext.new
    else
      deliver_error!(422, message: ERROR_INVALID_ENTITY_SPEC)
    end

    unless existing_hosts.include?(host)
      deliver_error!(404, message: ERROR_REPLICA_NOT_FOUND)
    end

    unless ctx.ok_to_queue_job?(host)
      deliver_error!(429, message: ERROR_HOST_TOO_BUSY)
    end

    ctx.enqueue_destroy_replica(id, host)
    deliver_raw({ status: "replica deletion scheduled for #{type}/#{id}" }, status: 202)
  end

  post "/internal/spokes/entities/:entity_type/:entity_id/replicas/recompute_checksums", operation_id: :internal, resolve_tenant_context: :resolve_tenant_from_entity do
    @route_owner = "@github/git-systems"

    type, id = entity_from_params
    delay = params["delay_s"].to_i.seconds

    case type
    when "gist"
      SpokesRecomputeGistChecksumsJob.set(wait: delay).perform_later(id)
    when "repo"
      SpokesRecomputeChecksumsJob.set(wait: delay).perform_later(id, false)
    when "wiki"
      SpokesRecomputeChecksumsJob.set(wait: delay).perform_later(id, true)
    else
      deliver_error!(422, message: ERROR_INVALID_ENTITY_SPEC)
    end

    deliver_raw({ status: "recompute checksums scheduled for #{type} #{id}" }, status: 200)
  end

  def entity_from_params
    type = params["entity_type"]
    id = params["entity_id"].to_i
    [type, id]
  end

  def repair_entity_from_params
    type, id = entity_from_params

    # A spec for a repo is in the form <network id>/<repository id>
    network_id = type.to_i
    if network_id > 0
      type = "repo"

      # A wiki spec is in the form of <network_id>/<repository_id>.wiki
      if params["entity_id"].end_with? ".wiki"
        type = "wiki"
      end

      return [type, id, network_id]
    end

    [type, id, network_id]
  end

  def resolve_tenant(type:, id:)
    case type
    when "repo", "wiki"
      ::Repositories::Public.resolve_tenant(id:)
    when "network"
      ::RepositoryNetworks::Public.resolve_tenant(id:)
    end
  end

  def resolve_tenant_from_entity
    type, id = entity_from_params
    resolve_tenant(type:, id:)
  end

  def resolve_tenant_from_repair_entity
    type, id, _ = repair_entity_from_params
    resolve_tenant(type:, id:)
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
end
