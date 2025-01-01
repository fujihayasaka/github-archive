# frozen_string_literal: true

class GitHubRepoImporter < ApplicationImporter
  def advisory_paths
    @backfill ? retrieve_current_advisory_paths : retrieve_updated_advisory_paths
  end

  def retrieve_current_advisory_paths
    branch = AdvisoryDB.github.repo(repo_nwo).default_branch
    advisory_folder_sha = AdvisoryDB.github.commit(repo_nwo, branch).commit.tree.sha

    if advisory_folder.present?
      # Split the path from "foo/bar/"" to ["foo", "bar"]
      path_names = Pathname(advisory_folder).each_filename.to_a

      # Descend into the directory and retrieve the non-recursive tree for the parent directory, return the SHA for the current directory
      advisory_folder_sha = path_names.inject(advisory_folder_sha) do |parent_directory_sha, path_name|
        AdvisoryDB.github.tree(repo_nwo, parent_directory_sha).tree.find { |item| item.path == path_name }.sha
      end
    end

    advisory_folder_content = AdvisoryDB.github.tree(repo_nwo, advisory_folder_sha, recursive: true)

    if advisory_folder_content.truncated
      raise NotImplementedError, "Need to build recursive tree fetching for very large repo"
    end

    advisory_folder_content.tree.filter_map { |item| item.type == "blob" ? "#{advisory_folder}#{item.path}" : nil }
  end

  def retrieve_updated_advisory_paths
    paths = Set.new

    fetch_commits.each do |commit|
      paths.merge(AdvisoryDB.github.commit(repo_nwo, commit.sha).files.map(&:filename))

      while AdvisoryDB.github.last_response.rels[:next].present?
        paths.merge(AdvisoryDB.github.get(AdvisoryDB.github.last_response.rels[:next].href).files.map(&:filename))
      end
    end

    paths.to_a.select { |path| path.starts_with?(advisory_folder) }
  end

  private

  def fetch_commits
    last_import = Import.where(source: source, bulk: true).where.not(finished_at: nil).last
    return [] unless last_import

    commits = AdvisoryDB.github.commits_since(
      repo_nwo,
      last_import.started_at,
      { path: advisory_folder },
    )

    while AdvisoryDB.github.last_response.rels[:next].present?
      commits += AdvisoryDB.github.get(AdvisoryDB.github.last_response.rels[:next].href)
    end

    commits
  end

  def advisory_folder
    self.class::ADVISORY_FOLDER
  end

  def repo_nwo
    self.class::REPO_NWO
  end
end
