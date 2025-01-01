# typed: strict
# frozen_string_literal: true

module PullRequests::PageData
  class HeaderSerializer
    extend T::Sig
    include GitHub::Memoizer

    class PullRequestData < T::Struct
      const :author, String
      const :baseBranch, String
      const :commitsCount, Integer
      const :headBranch, String
      const :headRepositoryName, T.nilable(String)
      const :headRepositoryOwnerLogin, T.nilable(String)
      const :isInAdvisoryRepo, T::Boolean
      const :linesAdded, T.nilable(Integer)
      const :linesChanged, T.nilable(Integer)
      const :linesDeleted, T.nilable(Integer)
      const :mergedBy, T.nilable(String)
      const :number, Integer
      const :state, String
      const :title, String
      const :titleHtml, String
    end

    class BaseRepositoryData < T::Struct
      const :codespacesEnabled, T::Boolean
      const :copilotEnabled, T::Boolean
      const :editorEnabled, T::Boolean
      const :defaultBranch, String
      const :id, Integer
      const :isEnterprise, T::Boolean
      const :name, String
      const :ownerLogin, String
    end

    class UrlsData < T::Struct
      const :checks, String
      const :commits, String
      const :conversation, T.nilable(String)
      const :files, String
    end

    class UserData < T::Struct
      const :canChangeBase, T::Boolean
      const :canEditTitle, T::Boolean
    end

    class HeaderData < T::Struct
      const :bannersData, T::Hash[Symbol, T::Hash[Symbol, T::Hash[Symbol, Object]]]
      const :pullRequest, PullRequestData
      const :repository, BaseRepositoryData
      const :urls, UrlsData
      const :user, UserData
    end

    sig do
      params(
        author_display_login: String,
        banners_data: T::Hash[Symbol, T::Hash[Symbol, T::Hash[Symbol, Object]]],
        base_repository: Repository,
        base_repository_default_branch: String,
        base_url: T.nilable(String),
        codespaces_enabled: T::Boolean,
        commit_count: Integer,
        copilot_enabled: T::Boolean,
        current_user_can_change_base: T::Boolean,
        current_user_can_edit_title: T::Boolean,
        editor_enabled: T::Boolean,
        head_owner: T.nilable(User),
        head_repository: T.nilable(Repository),
        is_enterprise: T::Boolean,
        is_in_advisory_repo: T::Boolean,
        lines_added: T.nilable(Integer),
        lines_changed: T.nilable(Integer),
        lines_deleted: T.nilable(Integer),
        merged_by: T.nilable(String),
        pull_request: PullRequest,
        pull_request_display_state: String,
      ).void
    end
    def initialize(
      author_display_login:,
      banners_data:,
      base_repository:,
      base_repository_default_branch:,
      base_url:,
      codespaces_enabled:,
      commit_count:,
      copilot_enabled:,
      current_user_can_change_base:,
      current_user_can_edit_title:,
      editor_enabled:,
      head_owner:,
      head_repository:,
      is_enterprise:,
      is_in_advisory_repo:,
      lines_added:,
      lines_changed:,
      lines_deleted:,
      merged_by:,
      pull_request:,
      pull_request_display_state:
    )
      @author_display_login = author_display_login
      @banners_data = banners_data
      @base_repository = base_repository
      @base_repository_default_branch = base_repository_default_branch
      @base_url = base_url
      @codespaces_enabled = codespaces_enabled
      @commit_count = commit_count
      @copilot_enabled = copilot_enabled
      @current_user_can_change_base = current_user_can_change_base
      @current_user_can_edit_title = current_user_can_edit_title
      @editor_enabled = editor_enabled
      @head_owner = head_owner
      @head_repository = head_repository
      @is_enterprise = is_enterprise
      @is_in_advisory_repo = is_in_advisory_repo
      @lines_added = lines_added
      @lines_changed = lines_changed
      @lines_deleted = lines_deleted
      @merged_by = merged_by
      @pull_request = T.let(pull_request, PullRequest)
      @pull_request_display_state = pull_request_display_state
    end

    sig { returns(T::Hash[String, T.untyped]) }
    def to_hash
      HeaderData.new(
        bannersData: @banners_data,
        pullRequest: PullRequestData.new(
          author: @author_display_login,
          baseBranch: @pull_request.display_base_ref_name,
          commitsCount: @commit_count,
          headBranch: @pull_request.display_head_ref_name,
          headRepositoryOwnerLogin: @head_owner&.display_login,
          headRepositoryName: @head_repository&.name,
          isInAdvisoryRepo: @is_in_advisory_repo,
          linesAdded: @lines_added,
          linesChanged: @lines_changed,
          linesDeleted: @lines_deleted,
          mergedBy: @merged_by,
          number: @pull_request.number,
          state: @pull_request_display_state,
          title: @pull_request.title,
          titleHtml: @pull_request.title_html,
        ),
        repository: BaseRepositoryData.new(
          codespacesEnabled: @codespaces_enabled,
          copilotEnabled: @copilot_enabled,
          editorEnabled: @editor_enabled,
          defaultBranch: @base_repository_default_branch,
          id: T.must(@base_repository.id),
          isEnterprise: @is_enterprise,
          name: T.must(@base_repository.name),
          ownerLogin: @base_repository.owner_display_login,
        ),
        urls: UrlsData.new(
          checks: "#{@base_url}/checks",
          commits: "#{@base_url}/commits",
          conversation: @base_url,
          files: "#{@base_url}/files",
        ),
        user: UserData.new(
          canChangeBase: @current_user_can_change_base,
          canEditTitle: @current_user_can_edit_title,
        ),
      ).as_json
    end
  end
end
