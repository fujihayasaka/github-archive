# typed: true
# frozen_string_literal: true
class Platform::Models::CommitRevision
  include GitHub::Relay::GlobalIdentification

  def self.load_from_global_id(id)
    repository_id, name = id.split(":", 2)

    Platform::Loaders::ActiveRecord.load(::Repository, repository_id.to_i, security_violation_behaviour: :nil).then do |repository|
      new(repository, name) if repository
    end
  end

  def self.valid_revision?(name)
    if name.start_with?(":/") # :/<text>
      false
    elsif name.match(/\^{\//) # <rev>^{/<text>}
      false
    else
      true
    end
  end

  def self.find(repository, name)
    new(repository, name) if valid_revision?(name)
  end

  attr_reader :repository, :name

  def initialize(repository, name)
    @repository = repository
    if name.is_a?(Commit)
      @commit = name
      @name = @commit.oid
    else
      @name = name
      @commit = nil
    end
  end

  def global_id
    "#{repository.id}:#{name}"
  end

  def async_repository
    Promise.resolve(repository)
  end

  def async_commit
    return @commit if @commit

    repository.async_network.then do
      # TODO: Use rev-parse loader
      repository.ref_to_sha(name)
    end.then do |oid|
      Platform::Loaders::GitObject.load(repository, oid) if oid
    end
  end

  def async_load_object(klass, file_path)
    async_commit.then do |commit|
      # TODO: Create TreeEntry platform loader
      if tree_entry = repository.tree_entry(commit.oid, file_path)
        klass.new(self, tree_entry, file_path, commit.oid)
      end
  rescue GitRPC::NoSuchPath
    nil
    end
  end

  def async_load_directory(path: nil)
    normalized_path = path.to_s.sub(/\A\//, "")
    @async_load_directory_cache ||= {}
    @async_load_directory_cache[path] ||= async_load_object(Platform::Models::CommittishDirectory, normalized_path)
  end

  def async_load_file(path:)
    normalized_path = path.sub(/\A\//, "")
    @async_load_file_cache ||= {}
    @async_load_file_cache[path] ||= async_load_object(Platform::Models::CommittishFile, normalized_path)
  end
end
