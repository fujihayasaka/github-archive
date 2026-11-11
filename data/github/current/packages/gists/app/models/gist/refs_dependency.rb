# typed: false
# frozen_string_literal: true

require "gh/interfaces/default_branch"

module Gist::RefsDependency
  include GH::Interfaces::DefaultBranch

  UNROUTED_EXCEPTIONS = [
    GitHub::DGit::NotFoundError,
    GitHub::DGit::UnroutedError,
    GitRPC::ConnectionError,
    GitRPC::RepositoryOffline,
    Repository::RpcDependency::UnroutedError,
  ].freeze

  # For API compatibility with Repository::RefsDependency
  def default_branch
    @default_branch ||= begin
      refname = self.get_default_branch
      if refname.starts_with?("refs/heads/")
        refname = refname.delete_prefix("refs/heads/")
      end
      refname.force_encoding("UTF-8")
    rescue SpokesAPI::ResourceExhausted
      # request was rate limited
      raise
    rescue GitRPC::InvalidRepository, SpokesAPI::NotFound
      gist_repo_default_branch
    rescue *UNROUTED_EXCEPTIONS => e
      Failbot.report!(e, app: "github-unrouted")
      gist_repo_default_branch
    rescue GitRPC::Error, SpokesAPI::Error => e
      Failbot.report!(e)
      gist_repo_default_branch
    end
  end

  # Public: This gist's refs.
  def refs
    return @refs if defined?(@refs)
    @refs = Git::Ref::Collection.new(loader: refs_loader)
  end

  # Public: Retrieve a ref collection for all branch refs in the gist.
  #
  # Returns a refs collection object with the prefix set to "refs/heads/".
  def heads
    return @heads if defined?(@heads)
    @heads = Git::Ref::Collection.new(loader: refs_loader, prefix: "refs/heads/")
  end

  private def refs_loader
    return @refs_loader if defined?(@refs_loader)
    @refs_loader = Git::Ref::Loader.new(self, "default")
  end

  # Public: Resolve a name or oid down to a commit oid.
  #
  # Returns a string commit oid when the revision is found, nil otherwise.
  def ref_to_sha(revision)
    if ref = refs.find(revision)
      ref.target_oid
    elsif GitRPC::Util.valid_full_oid?(revision)
      revision
    end
  end

  # Public: Current HEAD commit sha1.
  #
  # Returns nil if there was an error.
  def sha
    rpc.read_head_oid
  rescue GitRPC::Error, GitHub::DGit::UnroutedError
    nil
  rescue Errno::EHOSTUNREACH => boom
    Failbot.report boom, failbot_context
    nil
  end
  alias_method :default_oid, :sha

  # The oid of the main head commit.
  def master_oid
    return @master_oid if defined?(@master_oid)

    @master_oid =
      if ref = heads.find(default_branch)
        ref.target_oid
      end
  end

  # Public: Clear the refs caches. This forces a fetch of refs hash data from
  # the repository on disk the next time #refs or #extended_refs is accessed by
  # any process. Also forces subsequent Spokes API requests for this repository
  # to not use any cached responses.
  #
  # This should be called any time a ref is modified to make the change visible
  # to other processes. You typically don't need to worry about this if you're
  # using Ref#update since the refs cache is automatically cleared.
  #
  # Note that the refs cache key included the repository's pushed_at timestamp.
  # If the pushed_at timestamp on the receiver is not in sync with the database,
  # the wrong refs cache key will be cleared.
  #
  # Returns nothing.
  def clear_ref_cache
    rpc.clear_repository_reference_key!
    reset_refs
    spokes_api_context.read_after_write = true
  end

  # Public: Manually sets the cache key for the gitrpc cache. This allows
  # us to use the checksum passed back from a reference update to set the
  # cache key, rather than getting it from the database.
  #
  # This is useful in the case where we are making a reference update with
  # a transaction in Rails.
  def set_ref_cache_key(checksum)
    return if checksum.nil?

    rpc.set_repository_reference_key!(checksum)
  end

  def reset_refs
    remove_instance_variable(:@refs) if defined?(@refs)
    remove_instance_variable(:@refs_loader) if defined?(@refs_loader)
    remove_instance_variable(:@heads) if defined?(@heads)
  end
end
