# typed: true
# frozen_string_literal: true

class Platform::Models::CommittishObject
  extend T::Helpers
  extend T::Sig
  include GitHub::Relay::GlobalIdentification

  abstract!

  def self.load_from_global_id(id)
    repository_id, revision_name, file_path = id.split(":", 3)

    Platform::Loaders::ActiveRecord.load(::Repository, repository_id.to_i, security_violation_behaviour: :nil).then do |repository|
      next unless repository
      revision = Platform::Models::CommitRevision.new(repository, revision_name)
      revision.async_load_object(self, file_path)
    end
  end

  attr_reader :revision, :tree_entry, :file_path, :oid, :commit_oid

  def initialize(revision, tree_entry, file_path, commit_oid)
    @revision = revision
    @tree_entry = tree_entry
    @file_path = file_path
    @oid = tree_entry.oid
    @commit_oid = commit_oid

    if file_path.start_with?("/")
      # Don't include filepath in this message, which might leak private data
      raise Platform::Errors::Internal, "file_path must not start with leading \"/\""
    end

    GitRPC::Util.ensure_valid_full_sha1(oid)
  end

  def repository
    revision.repository
  end

  def async_repository
    Promise.resolve(repository)
  end

  def async_object
    Platform::Loaders::GitObject.load(repository, oid, path_prefix: tree_entry.path)
  end

  def platform_type_name
    type_name
  end

  sig  { abstract.returns(String) }
  def type_name; end

  def global_id
    "#{repository.id}:#{revision.name}:#{file_path}"
  end

  def uri_type
  end

  def uri
    paths = file_path.split("/").reject(&:blank?)

    template = Addressable::Template.new("/{owner}/{name}/{type}/{revision}{/path*}")
    template.expand(
      owner: repository.owner_display_login,
      name: repository.name,
      type: uri_type,
      revision: revision.name,
      path: paths.any? ? paths : nil,
    )
  end
end
