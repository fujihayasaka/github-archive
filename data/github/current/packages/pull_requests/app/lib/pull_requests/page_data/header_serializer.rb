# typed: strict
# frozen_string_literal: true

module PullRequests::PageData
  class HeaderSerializer
    include GitHub::Memoizer

    class AliveChannels < T::Struct
      const :pullRequest, String
      const :pullRequestState, String
      const :pullRequestTimeline, String
    end

    class Author < T::Struct
      const :login, String
      const :displayName, T.nilable(String)
    end

    class MergeStatusButtonData < T::Struct
      const :channels, PullRequests::PageData::MergeBox::PullRequestPayload::MergeBoxAliveChannels
      const :defaultMergeMethod, PullRequests::PageData::MergeBox::PullRequestPayload::MergeMethod
      const :headSha, String
      const :helpUrl, String
      const :viewerLogin, T.nilable(String)
    end

    class PullRequestData < T::Struct
      const :author, Author
      const :baseBranch, String
      const :commitsCount, Integer
      const :headBranch, String
      const :headRepositoryName, T.nilable(String)
      const :headRepositoryOwnerLogin, T.nilable(String)
      const :id, Integer
      const :isInAdvisoryRepo, T::Boolean
      const :mergedBy, T.nilable(String)
      const :mergedByName, T.nilable(String)
      const :mergedTime, T.nilable(String)
      const :number, Integer
      const :relayId, String
      const :state, String
      const :title, String
      const :titleHtml, String
    end

    class BaseRepositoryData < T::Struct
      const :codespacesEnabled, T::Boolean
      const :editorEnabled, T::Boolean
      const :defaultBranch, String
      const :id, Integer
      const :isEnterprise, T::Boolean
      const :name, String
      const :ownerLogin, String
      const :userNameDisplayConfiguration, T.nilable(String)
    end

    # NOTE: When modifying URL fields here, also update Files::Payload::UrlsData
    # to keep the base URL structure in sync. The Files page extends these URLs
    # with additional fields (e.g., images).
    class UrlsData < T::Struct
      const :changes, String
      const :checks, String
      const :commits, String
      const :conversation, T.nilable(String)
      const :files, String
      const :findings, String
      const :overview, String
      const :walkthrough, String
    end

    class UserViewSettings < T::Struct
      const :dockedPanelWidth, T.nilable(Integer)
    end

    class UserData < T::Struct
      const :canChangeBase, T::Boolean
      const :canEditTitle, T::Boolean
    end

    class HeaderData < T::Struct
      const :aliveChannel, String
      const :aliveChannels, PullRequests::PageData::HeaderSerializer::AliveChannels
      const :bannersData, T::Hash[Symbol, T::Hash[Symbol, T::Hash[Symbol, Object]]]
      const :mergeStatusButtonData, T.nilable(MergeStatusButtonData)
      const :pullRequest, PullRequestData
      const :repository, BaseRepositoryData
      const :urls, UrlsData
      const :user, UserData
      const :viewSettings, UserViewSettings
      const :pageTitle, String
      const :stack, T.nilable(Stack::Payload::StackData)
    end

    sig do
      params(
        alive_channels: PullRequests::PageData::HeaderSerializer::AliveChannels,
        author_display_login: String,
        author_display_name: T.nilable(String),
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
        merged_by: T.nilable(String),
        merged_by_name: T.nilable(String),
        merged_time: T.nilable(String),
        pull_request: PullRequest,
        pull_request_display_state: String,
        user_name_display_configuration: T.nilable(String),
        page_title: String,
        stack_data: T.nilable(Stack::Loader::Data),
        merge_status_button_data: T.nilable(PullRequests::PageData::MergeStatusButtonData),
        docked_panel_width: T.nilable(Integer),
      ).void
    end
    def initialize(
      alive_channels:,
      author_display_login:,
      author_display_name:,
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
      merged_by:,
      merged_by_name:,
      merged_time:,
      pull_request:,
      pull_request_display_state:,
      user_name_display_configuration:,
      page_title:,
      stack_data:,
      merge_status_button_data: nil,
      docked_panel_width: nil
    )
      @alive_channels = alive_channels
      @author_display_login = author_display_login
      @author_display_name = author_display_name
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
      @merge_status_button_data = merge_status_button_data
      @merged_by = merged_by
      @merged_by_name = merged_by_name
      @merged_time = merged_time
      @pull_request = T.let(pull_request, PullRequest)
      @pull_request_display_state = pull_request_display_state
      @user_name_display_configuration = user_name_display_configuration
      @page_title = page_title
      @stack_data = stack_data
      @docked_panel_width = docked_panel_width
    end

    sig { returns(T::Hash[String, T.untyped]) }
    def to_hash
      HeaderData.new(
        aliveChannel: @alive_channels.pullRequest, # leaving this for a bit for backward compatibility, but aliveChannels should be used going forward
        aliveChannels: @alive_channels,
        pageTitle: @page_title,
        bannersData: @banners_data,
        mergeStatusButtonData: serialize_merge_status_button_data,
        pullRequest: PullRequestData.new(
          author: Author.new(login: @author_display_login, displayName: @author_display_name),
          baseBranch: @pull_request.display_base_ref_name,
          commitsCount: @commit_count,
          headBranch: @pull_request.display_head_ref_name,
          headRepositoryOwnerLogin: @head_owner&.display_login,
          headRepositoryName: @head_repository&.name,
          id: @pull_request.id,
          isInAdvisoryRepo: @is_in_advisory_repo,
          mergedBy: @merged_by,
          mergedByName: @merged_by_name,
          mergedTime: @merged_time,
          number: @pull_request.number,
          relayId: @pull_request.global_relay_id,
          state: @pull_request_display_state,
          title: @pull_request.title,
          titleHtml: @pull_request.title_html,
        ),
        repository: BaseRepositoryData.new(
          codespacesEnabled: @codespaces_enabled,
          editorEnabled: @editor_enabled,
          defaultBranch: @base_repository_default_branch,
          id: @base_repository.id,
          isEnterprise: @is_enterprise,
          name: @base_repository.name,
          ownerLogin: @base_repository.owner_display_login,
          userNameDisplayConfiguration: @user_name_display_configuration,
        ),
        urls: UrlsData.new(
          changes: "#{@base_url}/changes",
          checks: "#{@base_url}/checks",
          commits: "#{@base_url}/commits",
          conversation: @base_url,
          files: "#{@base_url}/files",
          findings: "#{@base_url}/findings",
          overview: "#{@base_url}/overview",
          walkthrough: "#{@base_url}/walkthrough",
        ),
        user: UserData.new(
          canChangeBase: @current_user_can_change_base,
          canEditTitle: @current_user_can_edit_title,
        ),
        viewSettings: UserViewSettings.new(
          dockedPanelWidth: @docked_panel_width,
        ),
        stack: Stack::Payload.call(data: @stack_data),
      ).as_json
    end

    private

    sig { returns(T.nilable(MergeStatusButtonData)) }
    def serialize_merge_status_button_data
      return nil if @merge_status_button_data.nil?

      MergeStatusButtonData.new(
        channels: @merge_status_button_data.channels,
        defaultMergeMethod: @merge_status_button_data.default_merge_method,
        headSha: @merge_status_button_data.head_sha,
        helpUrl: @merge_status_button_data.help_url,
        viewerLogin: @merge_status_button_data.viewer_login,
      )
    end
  end
end
