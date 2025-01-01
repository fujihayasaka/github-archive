# typed: false
# frozen_string_literal: true

class ExploreRepositoryFileReader
  INDEX_FILE_NAME = "index.md"
  REPO_OWNER = "github"
  REPO_NAME = "explore"

  # Public: Returns the name and owner of the repository where collection data is expected to live.
  def self.repository_name_with_owner
    "#{REPO_OWNER}/#{REPO_NAME}"
  end

  def initialize(directory_path)
    @directory_path = directory_path
  end

  def all_directories
    unless repository
      raise RuntimeError.new("Missing public repository #{self.class.repository_name_with_owner}")
    end
    unless latest_sha
      raise RuntimeError.new("Could not determine latest commit for #{repository.nwo} in " +
                 "#{repository.default_branch} branch")
    end
    return @all_directories if @all_directories
    begin
      _id, tree_entries, _truncated = repository.tree_entries(latest_sha, @directory_path)
      @all_directories = tree_entries.select { |entry| entry.type == "tree" }
    rescue RuntimeError => e
      raise RuntimeError.new("Missing directory #{@directory_path}")
    end
  end

  def read_index_file(directory_name)
    path = File.join(@directory_path, directory_name, INDEX_FILE_NAME)
    entry = repository.blob(latest_sha, path)

    return unless entry && entry.data

    parts = entry.data.split("---", 3)
    return unless parts.length == 3

    _, yaml, body = parts
    metadata = YAML.safe_load(yaml)
    [metadata, body.strip]
  end

  def url_from(name, file_name)
    return unless file_name

    dir_path = File.join(@directory_path, name)
    dir = repository.directory(latest_sha, dir_path)
    return unless dir

    tree_history = dir.tree_history
    commit = tree_history.load_or_calculate_single_entry(file_name)
    return unless commit

    host = "#{GitHub.scheme}://#{GitHub.urls.raw_host_name}"
    path = "/#{repository.nwo}/#{commit.oid}/#{@directory_path}/#{name}/#{file_name}"

    "#{host}#{path}"
  end

  def latest_sha
    @latest_sha ||= repository.heads.find(repository.default_branch).try(:target_oid)
  end

  def repository
    @repository ||= Repository.public_scope.with_name_with_owner(REPO_OWNER, REPO_NAME)
  end
end
