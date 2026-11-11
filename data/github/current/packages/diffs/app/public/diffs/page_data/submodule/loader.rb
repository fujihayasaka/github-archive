# typed: strict
# frozen_string_literal: true

module Diffs::PageData::Submodule
  class Loader
    include UrlHelper

    class Data < T::Struct
      const :base_path, String
      const :changed_files, T.nilable(Integer)
      const :contents_url, T.nilable(String)
      const :diff_entry, GitHub::Diff::Entry
      const :path_link, T.nilable(String)
      const :summary_deltas, T::Array[GitRPC::Diff::Summary::Delta]
    end

    sig do
      params(
        diff_entry: GitHub::Diff::Entry,
        repository: Repository,
        current_user: T.nilable(User),
      ).returns(T.nilable(Data))
    end
    def self.load(diff_entry:, repository:, current_user: nil)
      new(diff_entry:, repository:, current_user:).load
    end

    sig do
      params(
        diff_entry: GitHub::Diff::Entry,
        repository: Repository,
        current_user: T.nilable(User),
      ).void
    end
    def initialize(diff_entry:, repository:, current_user:)
      @diff_entry = diff_entry
      @repository = repository
      @current_user = current_user
    end

    sig { returns(T.nilable(Data)) }
    def load
      submodule = @repository.submodule(@diff_entry.b_sha, @diff_entry.path)
      return unless submodule

      submodule_repository = submodule_repo(submodule, @current_user)
      submodule_path_link = submodule&.linkable_url if submodule&.url_is_linkable?
      submodule_contents_url = submodule_content_url(submodule, nil, false) if submodule_diff_linkable?(submodule, @diff_entry)

      diff_summary = submodule_diff_summary(submodule_repository, @diff_entry)

      changed_files = diff_summary.changed_files if diff_summary&.available?
      summary_deltas = diff_summary.deltas if diff_summary&.available? && changed_files < MAX_DIFF_STATS_FILES

      Data.new(
        base_path: File.basename(@diff_entry.path),
        changed_files: changed_files,
        contents_url: submodule_contents_url,
        diff_entry: @diff_entry,
        path_link: submodule_path_link,
        summary_deltas: summary_deltas || [],
      )
    end

    private

    MAX_DIFF_STATS_FILES = 100

    sig { params(submodule: Submodule, diff_entry: GitHub::Diff::Entry).returns(T::Boolean) }
    def submodule_diff_linkable?(submodule, diff_entry)
      return false if diff_entry.added? && diff_entry.b_blob.nil?
      return false if diff_entry.deleted? && diff_entry.a_blob.nil?
      return false if diff_entry.a_blob.nil? && diff_entry.b_blob.nil?

      submodule.user.present? && submodule.repo.present?
    end

    sig { params(submodule: Submodule, current_user: T.nilable(User)).returns(T.nilable(Repository)) }
    def submodule_repo(submodule, current_user)
      return if submodule.user.nil? || submodule.repo.nil?

      nwo = "#{submodule.user}/#{submodule.repo}"
      return unless repo = Repository.nwo(nwo)
      return unless repo.permit?(current_user, :read)

      repo
    end

    sig { params(submodule_repo: T.nilable(Repository), diff_entry: GitHub::Diff::Entry).returns(T.nilable(GitRPC::Diff::Summary)) }
    def submodule_diff_summary(submodule_repo, diff_entry)
      return unless submodule_repo
      return if diff_entry.a_blob.nil? || diff_entry.b_blob.nil?

      diff = GitHub::Diff.new(submodule_repo, diff_entry.a_blob, diff_entry.b_blob,
                              base_sha: diff_entry.a_blob)
      diff.summary
    end
  end
end
