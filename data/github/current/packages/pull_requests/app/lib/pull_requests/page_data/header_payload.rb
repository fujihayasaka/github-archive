# typed: strict
# frozen_string_literal: true

module PullRequests::PageData
  class HeaderPayload
    include GitHub::ResilienceMixin
    include CurrentRepositoryInteractionsHelper
    include PullRequests::PageData::Telemetry
    include PullRequests::PageTitleHelper

    COMMITS_COUNT_FALLBACK = 0
    CURRENT_USER_CAN_CHANGE_BASE_FALLBACK = false
    CURRENT_USER_CAN_EDIT_TITLE_FALLBACK = false
    IS_IN_ADVISORY_REPO_FALLBACK = false
    USER_NAME_DISPLAY_CONFIGURATION_FALLBACK = Configurable::UserNameDisplayConfiguration::HANDLE

    sig { returns(T.nilable(User)) }
    attr_reader :current_user

    sig { returns(PullRequest) }
    attr_reader :pull_request

    class AliveChannels < T::Struct
      const :pullRequest, String
      const :pullRequestState, String
      const :pullRequestTimeline, String
    end

    sig do
      params(
        current_user: T.nilable(User),
        pull_request: PullRequest,
      ).returns(T::Hash[String, T.untyped])
    end
    def self.build(current_user:, pull_request:)
      new(current_user:, pull_request:).build
    end

    sig { params(current_user: T.nilable(User), pull_request: PullRequest).void }
    def initialize(current_user:, pull_request:)
      @current_user = current_user
      @pull_request = pull_request
    end

    sig { returns(T::Hash[String, T.untyped]) }
    def build
      with_telemetry do
        banners_data = PullRequests::PageData::BannersDataPayload.build(
          current_user: @current_user,
          pull_request: @pull_request,
          repository: current_repository,
        )
        commit_count = COMMITS_COUNT_FALLBACK

        alive_channels = PullRequests::PageData::HeaderSerializer::AliveChannels.new(
          pullRequest: GitHub::WebSocket::Channels.signed_pull_request(@pull_request),
          pullRequestState: GitHub::WebSocket::Channels.signed_pull_request_state(@pull_request),
          pullRequestTimeline: GitHub::WebSocket::Channels.signed_pull_request_timeline(@pull_request)
        )

        author_display_login = pull_request.safe_user.display_login
        author_display_name = pull_request.safe_user.profile_name
        base_url = pull_request.permalink(include_host: false)
        base_repository_default_branch = current_repository.default_branch
        head_repository = pull_request.head_repository
        head_owner = head_repository.nil? ? pull_request.head_user : head_repository.owner
        merged_by = pull_request.merged_by&.display_login
        merged_by_name = pull_request.merged_by&.profile_name
        merged_time = pull_request.merged_at&.iso8601&.to_s

        begin
          commit_count = @pull_request.historical_comparison.total_commits
        rescue GitRPC::Error => error
          Failbot.report error
        end

        current_user_can_change_base = \
          with_database_error_fallback(fallback: CURRENT_USER_CAN_CHANGE_BASE_FALLBACK) do
            pull_request.can_change_base_branch? && T.must(pull_request.issue).can_modify?(current_user)
          end

        current_user_can_edit_title = \
          with_database_error_fallback(fallback: CURRENT_USER_CAN_EDIT_TITLE_FALLBACK) do
            T.must(pull_request.issue).can_modify?(current_user)
          end

        is_in_advisory_repo = \
          with_database_error_fallback(fallback: IS_IN_ADVISORY_REPO_FALLBACK) do
            T.must(pull_request.in_advisory_workspace?)
          end

        pull_request_display_state = \
          with_database_error_fallback(fallback: pull_request.state.to_s.upcase) do
            PullRequest::Icon::State.for_pull_request(pull_request).to_s.upcase
          end

        codespaces_enabled = \
          with_database_error_fallback(fallback: false) do
            !!current_user&.codespaces_feature_enabled?
          end

        copilot_enabled = \
          with_database_error_fallback(fallback: false) do
            !!current_user&.feature_flag_enabled?(:copilot_workspace, default: false)
          end

        editor_enabled = \
          with_database_error_fallback(fallback: false) do
            !!current_user&.workspace_editor_preview_enabled?(repository: current_repository)
          end

        user_name_display_configuration = \
          with_database_error_fallback(fallback: USER_NAME_DISPLAY_CONFIGURATION_FALLBACK) do
            current_repository.organization&.user_name_display_configuration_value
          end

        stack_data = Stack::Loader.load(pull_request:, current_user:, repository: current_repository)

        PullRequests::PageData::HeaderSerializer.new(
          alive_channels:,
          author_display_login:,
          author_display_name:,
          banners_data:,
          base_repository: current_repository,
          base_repository_default_branch:,
          base_url:,
          codespaces_enabled:,
          commit_count:,
          copilot_enabled:,
          current_user_can_change_base:,
          current_user_can_edit_title:,
          docked_panel_width:,
          editor_enabled:,
          head_owner:,
          head_repository:,
          is_enterprise: GitHub.enterprise?,
          is_in_advisory_repo:,
          merge_status_button_data:,
          merged_by:,
          merged_by_name:,
          merged_time:,
          pull_request:,
          pull_request_display_state:,
          user_name_display_configuration:,
          page_title: pull_request_page_title(pull_request),
          stack_data:,
        ).to_hash
      end
    end

    private

    sig { returns(Repository) }
    def current_repository
      T.must(pull_request.repository)
    end

    sig { returns(T.nilable(Integer)) }
    def docked_panel_width
      return nil if @current_user.nil?

      @current_user.settings.get(:pull_request_docked_panel_width)
    end

    sig { returns(T.nilable(PullRequests::PageData::MergeStatusButtonData)) }
    def merge_status_button_data
      if current_user && FeatureFlag.vexi.enabled?(:pull_request_merge_status_button, current_user, default: false)
        return PullRequests::PageData::MergeStatusButtonData.new(pull_request: pull_request, viewer: T.must(current_user))
      end
      nil
    end
  end
end
