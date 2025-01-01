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

    destination_repository.rpc.backend.delegate.get_write_routes.each do |dgit_route|
      repo_backend_rpc = dgit_route.build_maint_rpc
      repo_backend_rpc.bare_clone(remote_url, dgit_route.path)
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
