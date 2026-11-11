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

    class AllowedNonCommentReviewType < T::Enum
      enums do
        APPROVE = new("APPROVE")
        REQUEST_CHANGES = new("REQUEST_CHANGES")
      end
    end

    class Author < T::Struct
      const :login, String
      const :displayName, T.nilable(String)
      const :avatarUrl, T.nilable(String)
    end

    class MergeStatusButtonData < T::Struct
      const :channels, PullRequests::PageData::MergeBox::AliveChannelsPayload::Data
      const :defaultMergeMethod, PullRequests::PageData::MergeBox::PullRequestPayload::MergeMethod
      const :headSha, String
      # Remove this field when the client has been updated to use the top level HeaderData helpUrl field instead
      const :helpUrl, String
      const :viewerLogin, T.nilable(String)
    end

    class PullRequestData < T::Struct
      const :author, Author
      const :baseBranch, String
      const :closedTime, T.nilable(String)
      const :commitsCount, Integer
      const :createdTime, T.nilable(String)
      const :headBranch, String
      const :headRepositoryName, T.nilable(String)
      const :headRepositoryOwnerLogin, T.nilable(String)
      const :headSha, String
      const :id, Integer
      const :isInAdvisoryRepo, T::Boolean
      const :mergedBy, T.nilable(String)
      const :mergedByName, T.nilable(String)
      const :mergedByAvatarUrl, T.nilable(String)
      const :mergedTime, T.nilable(String)
      const :number, Integer
      const :relayId, String
      const :state, String
      const :title, String
      const :titleHtml, String
      const :viewerAllowedNonCommentReviewTypes, T::Array[AllowedNonCommentReviewType]
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
      const :canComment, T::Boolean
      const :canEditTitle, T::Boolean
      const :notices, T::Array[PullRequests::PageData::UserNotices::Payload::Notice]
    end

    class HeaderData < T::Struct
      const :aliveChannel, String
      const :aliveChannels, PullRequests::PageData::HeaderSerializer::AliveChannels
      const :bannersData, T::Hash[Symbol, T::Hash[Symbol, T::Hash[Symbol, Object]]]
      const :featureStates, FeatureStates::Payload::FeatureStatesData
      const :helpUrl, String
      const :mergeStatusButtonData, T.nilable(MergeStatusButtonData)
      const :pullRequest, PullRequestData
      const :repository, BaseRepositoryData
      const :urls, UrlsData
      const :user, UserData
      const :viewerPendingReview, T.nilable(PullRequests::PageData::Files::ReviewMenu::Payload::PendingReview)
      const :viewSettings, UserViewSettings
      const :pageTitle, String
      const :stack, T.nilable(Stack::Payload::StackData)
    end

    sig do
      params(
        alive_channels: PullRequests::PageData::HeaderSerializer::AliveChannels,
        author_display_login: String,
        author_display_name: T.nilable(String),
        author_avatar_url: T.nilable(String),
        banners_data: T::Hash[Symbol, T::Hash[Symbol, T::Hash[Symbol, Object]]],
        base_repository: Repository,
        base_repository_default_branch: String,
        base_url: T.nilable(String),
        codespaces_enabled: T::Boolean,
        commit_count: Integer,
        copilot_enabled: T::Boolean,
        current_user_can_change_base: T::Boolean,
        current_user_can_comment: T::Boolean,
        current_user_can_edit_title: T::Boolean,
        editor_enabled: T::Boolean,
        feature_states_data: FeatureStates::Loader::Data,
        head_owner: T.nilable(User),
        head_repository: T.nilable(Repository),
        help_url: String,
        is_enterprise: T::Boolean,
        is_in_advisory_repo: T::Boolean,
        created_time: T.nilable(String),
        closed_time: T.nilable(String),
        merged_by: T.nilable(String),
        merged_by_name: T.nilable(String),
        merged_by_avatar_url: T.nilable(String),
        merged_time: T.nilable(String),
        pull_request: PullRequest,
        pull_request_display_state: String,
        user_name_display_configuration: T.nilable(String),
        page_title: String,
        stack_data: T.nilable(Stack::Loader::Data),
        user_notices_data: PullRequests::PageData::UserNotices::Loader::Data,
        merge_status_button_data: T.nilable(PullRequests::PageData::MergeStatusButtonData),
        docked_panel_width: T.nilable(Integer),
        viewer_allowed_non_comment_review_types: T::Array[AllowedNonCommentReviewType],
        viewer_pending_review_data: T.nilable(PullRequests::PageData::Files::ReviewMenu::Loader::PendingReview),
      ).void
    end
    def initialize(
      alive_channels:,
      author_display_login:,
      author_display_name:,
      author_avatar_url:,
      banners_data:,
      base_repository:,
      base_repository_default_branch:,
      base_url:,
      codespaces_enabled:,
      commit_count:,
      copilot_enabled:,
      current_user_can_change_base:,
      current_user_can_comment:,
      current_user_can_edit_title:,
      editor_enabled:,
      feature_states_data:,
      head_owner:,
      head_repository:,
      help_url:,
      is_enterprise:,
      is_in_advisory_repo:,
      created_time:,
      closed_time:,
      merged_by:,
      merged_by_name:,
      merged_by_avatar_url:,
      merged_time:,
      pull_request:,
      pull_request_display_state:,
      user_name_display_configuration:,
      page_title:,
      stack_data:,
      user_notices_data:,
      merge_status_button_data: nil,
      docked_panel_width: nil,
      viewer_allowed_non_comment_review_types: [],
      viewer_pending_review_data: nil
    )
      @alive_channels = alive_channels
      @author_display_login = author_display_login
      @author_display_name = author_display_name
      @author_avatar_url = author_avatar_url
      @banners_data = banners_data
      @base_repository = base_repository
      @base_repository_default_branch = base_repository_default_branch
      @base_url = base_url
      @codespaces_enabled = codespaces_enabled
      @commit_count = commit_count
      @copilot_enabled = copilot_enabled
      @current_user_can_change_base = current_user_can_change_base
      @current_user_can_comment = current_user_can_comment
      @current_user_can_edit_title = current_user_can_edit_title
      @editor_enabled = editor_enabled
      @feature_states_data = feature_states_data
      @head_owner = head_owner
      @head_repository = head_repository
      @help_url = help_url
      @is_enterprise = is_enterprise
      @is_in_advisory_repo = is_in_advisory_repo
      @merge_status_button_data = merge_status_button_data
      @created_time = created_time
      @closed_time = closed_time
      @merged_by = merged_by
      @merged_by_name = merged_by_name
      @merged_by_avatar_url = merged_by_avatar_url
      @merged_time = merged_time
      @pull_request = T.let(pull_request, PullRequest)
      @pull_request_display_state = pull_request_display_state
      @user_name_display_configuration = user_name_display_configuration
      @page_title = page_title
      @stack_data = stack_data
      @user_notices_data = user_notices_data
      @docked_panel_width = docked_panel_width
      @viewer_allowed_non_comment_review_types = viewer_allowed_non_comment_review_types
      @viewer_pending_review_data = viewer_pending_review_data
    end

    sig { returns(T::Hash[String, T.untyped]) }
    def to_hash
      HeaderData.new(
        aliveChannel: @alive_channels.pullRequest, # leaving this for a bit for backward compatibility, but aliveChannels should be used going forward
        aliveChannels: @alive_channels,
        pageTitle: @page_title,
        bannersData: @banners_data,
        featureStates: FeatureStates::Payload.call(data: @feature_states_data),
        helpUrl: @help_url,
        mergeStatusButtonData: serialize_merge_status_button_data,
        pullRequest: PullRequestData.new(
          author: Author.new(login: @author_display_login, displayName: @author_display_name, avatarUrl: @author_avatar_url),
          baseBranch: @pull_request.display_base_ref_name,
          closedTime: @closed_time,
          commitsCount: @commit_count,
          createdTime: @created_time,
          headBranch: @pull_request.display_head_ref_name,
          headRepositoryOwnerLogin: @head_owner&.display_login,
          headRepositoryName: @head_repository&.name,
          headSha: @pull_request.head_sha,
          id: @pull_request.id,
          isInAdvisoryRepo: @is_in_advisory_repo,
          mergedBy: @merged_by,
          mergedByName: @merged_by_name,
          mergedByAvatarUrl: @merged_by_avatar_url,
          mergedTime: @merged_time,
          number: @pull_request.number,
          relayId: @pull_request.global_relay_id,
          state: @pull_request_display_state,
          title: @pull_request.title,
          titleHtml: @pull_request.title_html,
          viewerAllowedNonCommentReviewTypes: @viewer_allowed_non_comment_review_types,
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
          canComment: @current_user_can_comment,
          canEditTitle: @current_user_can_edit_title,
          notices: PullRequests::PageData::UserNotices::Payload.call(@user_notices_data.notices),
        ),
        viewerPendingReview: serialize_viewer_pending_review,
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

    sig { returns(T.nilable(PullRequests::PageData::Files::ReviewMenu::Payload::PendingReview)) }
    def serialize_viewer_pending_review
      return nil if @viewer_pending_review_data.nil?

      PullRequests::PageData::Files::ReviewMenu::Payload.call(@viewer_pending_review_data)
    end
  end
end
