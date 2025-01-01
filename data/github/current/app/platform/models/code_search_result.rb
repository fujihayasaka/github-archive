# typed: true
# frozen_string_literal: true

class Platform::Models::CodeSearchResult
  attr_reader :path,
    :snippets,
    :commit_sha,
    :ref_name,
    :blob_sha,
    :language,
    :match_count,
    :repo_owner_id,
    :repo_id,
    :repo_nwo,
    :repository

  def initialize(
    path:,
    commit_sha:,
    ref_name:,
    blob_sha:,
    match_count:,
    repo_owner_id:,
    repo_id:,
    repo_nwo:,
    repository:,
    language: nil,
    snippets: []
  )
    @path          = path.to_s
    @repo_owner_id = repo_owner_id
    @repo_id       = repo_id
    @repo_nwo      = repo_nwo.to_s
    @snippets      = snippets || []
    @commit_sha    = commit_sha.to_s
    @ref_name      = ref_name.to_s
    @blob_sha      = blob_sha.to_s
    @language      = language
    @match_count   = match_count.to_i
    @repository    = repository
  end
end
