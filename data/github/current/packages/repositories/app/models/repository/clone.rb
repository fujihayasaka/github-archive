# typed: true
# frozen_string_literal: true

class Repository::Clone
  attr_reader :source_repository, :destination_repository

  def self.from_repo(source_repo:, destination_repo:)
    self.new(source_repo, destination_repo).from_repo
  end

  def initialize(source_repository, destination_repository)
    @source_repository = source_repository
    @destination_repository = destination_repository
  end

  def from_repo
    return unless source_repository
    remote_url = source_repository.internal_remote_url

    if FeatureFlag.vexi.enabled?(:repository_clone_job_resumable, destination_repository, default: false)
      # First, identify which routes have already been cloned.
      write_routes = destination_repository.rpc.backend.delegate.get_write_routes
      raise GitHub::DGit::UnroutedError, "no write routes found for destination repository" if write_routes.empty?
      existing_routes = write_routes.select do |dgit_route|
        repo_backend_rpc = dgit_route.build_maint_rpc
        repo_backend_rpc.exist?
      end

      if existing_routes.empty?
        # If no routes have been cloned yet, clone from the source repository to
        # the first replica.
        dgit_route = write_routes.first
        dgit_route.build_maint_rpc.bare_clone(remote_url, dgit_route.path)
        existing_routes << dgit_route
      end

      # Clone from the "donor" replica in the destination to the remaining
      # destination replicas. This ensures we do not race with pushes to the
      # source repository, potentially ending up with inconsistent replica
      # states in the destination.
      remote_url = existing_routes.first.remote_url
      write_routes.each do |dgit_route|
        # Skip cloning if the replica is already initialized
        next if existing_routes.include? dgit_route

        # Otherwise, clone from the donor replica
        repo_backend_rpc = dgit_route.build_maint_rpc
        repo_backend_rpc.bare_clone(remote_url, dgit_route.path)
      end
    else
      destination_repository.rpc.backend.delegate.get_write_routes.each do |dgit_route|
        repo_backend_rpc = dgit_route.build_maint_rpc
        repo_backend_rpc.bare_clone(remote_url, dgit_route.path)
      end
    end

    destination_repository.correct_hooks_symlink
    destination_repository.write_nwo_file_unsafe
    destination_repository.async_backup(opts: { pushed_at: Time.now })

    emit_completion
  end

  def emit_completion
    if !GitHub.enterprise?
      GlobalInstrumenter.instrument("repository.internal_clone_complete", to_h)
    end
  end

  def to_h
    {
      source_repository: source_repository,
      destination_repository: destination_repository
    }
  end
end
