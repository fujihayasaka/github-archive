# typed: false
# frozen_string_literal: true

require "gh/interfaces/git_rpc"

module Gist::DGit
  include GH::Interfaces::GitRPC

  def dgit_repo_type
    GitHub::DGit::RepoType::GIST
  end

  def coalesce_dgit_updates?
    false
  end

  # dgit_spec is the canonical description for a repository entity within
  # dgit/spokes. It avoids using any PII.
  def dgit_spec
    "gist/#{id}"
  end

  def route
    dgit_read_routes.first.host
  end
  alias host route

  def delete_replicas_and_checksums_after_commit_on_destroy
    GitHub::DGit::Maintenance.delete_gist_replicas_and_checksums(self.id)
  end

  # Public: original_shard_path defines the path on a fileserver's disk for the repository
  def original_shard_path
    GitHub::Routing.gist_storage_path(repo_name: repo_name)
  end

  # Public: shard_path defines the path on disk for a repository.
  # It is distinct from original_shard_path in a dev/test environment where
  # "fileservers" are virtual and share the same disk.
  def shard_path
    if Rails.env.development? || Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
      original_host = dgit_read_routes.first.original_host
      # map route to a dgit subdirectory in dev and test
      GitHub::DGit.dev_route(original_shard_path, original_host)
    else
      original_shard_path
    end
  end

  # Public: The GitRPC::Client object used to retrieve git objects and
  # perform repository commands. The client is configured to cache aggressively.
  #
  # See https://github.com/github/gitrpc for project information.
  #
  # Returns the GitRPC::Client object.
  def rpc
    return @rpc if @rpc

    new_rpc = GitRPC.new("dgit:/", delegate: dgit_delegate)
    new_rpc.content_key = "gitrpc:gist:#{repo_name}"
    new_rpc.repository_key = "gitrpc:gist:#{repo_name}"
    new_rpc.feature_enabled = self.method(:feature_flag_enabled_or_raise?)
    new_rpc.options[:info] = {
      real_ip: GitHub.context[:actor_ip],
      request_id: GitHub.context[:request_id],
    }

    @rpc = new_rpc
  end

  def reset_rpc
    @rpc = nil
    @dgit_delegate = nil
  end

  def dgit_delegate_for_update_refs_coordinator
    dgit_delegate
  end

  def dgit_delegate
    return @dgit_delegate if @dgit_delegate

    raise GitHub::DGit::Error, "delegate requires an id" if id.nil?

    self.dgit_delegate = GitHub::DGit::Delegate::Gist.new(id, repo_name, original_shard_path, spokes_api_context)
  end

  def dgit_delegate=(delegate)
    # Reset our RPC client because it most likely has a copy of our previous delegate
    reset_rpc

    @dgit_delegate = delegate
  end

  def running_on_cache_server?
    !!ENV["ENTERPRISE_CLUSTER_CACHE_LOCATION"]
  end

  # Get all routes that can be used for read-only operations, in order of preference.
  def dgit_read_routes(cache_servers_ok: false)
    # Cache Servers never store or serve gists.
    return [] if running_on_cache_server?

    return @dgit_read_routes if @dgit_read_routes

    # Use the current RPC handle's backend delegate rather than insantiating a
    # new one via GitHub::DGit::Delegate: the RPC handle is memoized such
    # that backend hosts can be retrieved before any record of this gist has
    # been inserted into the database.
    @dgit_read_routes = dgit_delegate.get_read_routes
  end
  alias dgit_all_routes dgit_read_routes

  # Get all routes that can be used for write operations, in order of preference.
  def dgit_write_routes
    return @dgit_write_routes if @dgit_write_routes

    @dgit_write_routes = dgit_delegate.get_write_routes
  end

  # Clear all remembered DGit routes.
  def dgit_reload_routes!
    reset_rpc
    @dgit_read_routes = @dgit_write_routes = nil
  end

  # Is the Gist server online and serving requests?
  def online?
    begin
      rpc.online?
    rescue GitRPC::InvalidRepository => boom
      # If the repo is unrouted, we don't want to proceed with
      # git access (which blows up). But we also want to record
      # the problem repo to a special bucket.
      Failbot.push(app: "github-unrouted")
      Failbot.report(boom, failbot_context)
      false
    end
  end

  # Determine if this Gist is offline. This accounts for the storage
  # server being down and also for cases where the storage server is up but the
  # Gist is not available on disk due to the partition not being mounted
  # or a move being in progress.
  #
  # Returns true if the Gist's storage server is offline or if the
  # repository doesn't exist on disk more than five minutes after being created.
  def offline?
    !online? ||
      (created_at < 5.minutes.ago && !exists_on_disk?)
  end

  # Check if the repository directly exists on disk on the storage server. This
  # always makes an RPC call and should be used sparingly. Just because a
  # repository exists does not necessarily mean it has any branches, tags, or
  # other objects. The #empty? method is often a much better check for whether a
  # repository is in a useful state.
  #
  # If the repository isn't routed, returns false since there's no repo to check.
  #
  # Returns true when the repository exists.
  def exists_on_disk?
    shard_path && rpc.exist?
  rescue GitHub::DGit::UnroutedError
    false
  end
end
