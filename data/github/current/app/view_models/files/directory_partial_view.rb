# typed: true
# frozen_string_literal: true

module Files
  # Controls the listing of a directory of files and subdirectories.
  class DirectoryPartialView
    include ActionView::Helpers::TagHelper
    include GitHub::Encoding
    include GitHub::UTF8
    include CodeNavigationHelper
    include ResilienceHelper

    attr_reader :user, :repository, :directory, :path, :branch_or_tag_name, :commit_sha

    def initialize(user, repository, commit_sha, branch_or_tag_name, path, directory = nil)
      @user = user
      @repository = repository
      @commit_sha = commit_sha
      @branch_or_tag_name = branch_or_tag_name
      @path = path
      @directory = (directory || repository.directory(commit_sha, path))
    end

    def base_branch_range
      @base_branch_range ||= repository.base_branch(branch_or_tag_name, user, include_remote_repo: true, repo_seperator: ":")
    end

    def base_branch_range_encoded
      # We have several frozen string literal branch names. Avoid an exception by checking for frozen.
      @base_branch_range_encoded ||= base_branch_range.frozen? ? base_branch_range : base_branch_range.force_encoding("utf-8").scrub
    end

    def base_branch
      @base_branch ||= repository.base_branch(branch_or_tag_name, user)
    end

    def base_branch_encoded
      # We have several frozen string literal branch names. Avoid an exception by checking for frozen.
      @base_branch_encoded ||= base_branch.frozen? ? base_branch : base_branch.force_encoding("utf-8").scrub
    end

    def base_branch_with_repo
      @base_branch_with_repo ||= repository.base_branch(branch_or_tag_name, user, include_remote_repo: true)
    end

    def base_branch_with_repo_encoded
      # We have several frozen string literal branch names. Avoid an exception by checking for frozen.
      @base_branch_with_repo_encoded ||= base_branch_with_repo.frozen? ? base_branch_with_repo : base_branch_with_repo.force_encoding("utf-8").scrub
    end

    def comparison
      @comparison ||= GitHub::Comparison.deprecated_build(repository, base_branch, commit_sha, base_repo: repository.parent)
    end

    # Is there a pull request for this branch?
    #
    # Returns a PullRequest or false.
    def pull_request
      with_database_error_fallback(fallback: false) do
        @pull_request ||= begin
          pull = repository.pull_requests.for_branch(branch_or_tag_name).last
          return false unless pull && pull.open?
          return false if pull.safe_user.spammy?
          pull
        end
      end
    end


    delegate :has_readme?, to: :directory, allow_nil: true

    def readme
      directory.preferred_readme
    end

    # Is the readme editable by the current user?
    #
    # Returns a boolean.
    def edit_readme_enabled?
      with_database_error_fallback(fallback: false) do
        return false if repository.locked_on_migration?
        # readme editing is disabled when viewing on a tag.
        return false if branch_or_tag_name && !branch?
        has_readme? && repository.pushable_by?(user, ref: branch_or_tag_name)
      end
    end

    def readme_name_for_display
      utf8(readme.name.dup)
    end

    def subdirectory?
      !@path.blank?
    end

    def branch?
      repository.heads.exist?(branch_or_tag_name)
    end

    def render_directory_entries?
      directory && (directory.history_cached? || !directory.can_compute_history?)
    end

    # Public: Can we load latest commit information. Only possible if we can
    # compute history for the directory.
    def can_load_latest_commit_information?
      directory.can_compute_history?
    end

    def upload_enabled?
      branch_or_tag_name&.b.present?
    end
  end
end
