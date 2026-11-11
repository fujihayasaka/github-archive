# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::ReviewMenuData
  class Loader
    include GitHub::ResilienceMixin

    class ViewerPermission < T::Enum
      enums do
        Read = new("READ")
        Triage = new("TRIAGE")
        Write = new("WRITE")
        Maintain = new("MAINTAIN")
        Admin = new("ADMIN")
      end
    end

    PERMISSION_FALLBACK = ViewerPermission::Read

    class ReviewMenuData < T::Struct
      const :viewer_has_violated_push_policy, T::Boolean
      const :viewer_is_copilot_attributed, T::Boolean
      const :viewer_permission, ViewerPermission
      const :threads, T::Array[PullRequests::PageData::Threads::Loader::PullRequestThreadData]
    end

    sig do
      params(
        pull_request: PullRequest,
        current_user: T.nilable(User),
        thread_ids: T::Array[Integer],
        limit_config: T.nilable(PullRequests::PageData::Files::PageLimitConfig),
      ).returns(ReviewMenuData)
    end
    def self.load(pull_request:, current_user:, thread_ids: [], limit_config: nil)
      new(pull_request:, current_user:, thread_ids:, limit_config:).load
    end

    sig do
      params(
        pull_request: PullRequest,
        current_user: T.nilable(User),
        thread_ids: T::Array[Integer],
        limit_config: T.nilable(PullRequests::PageData::Files::PageLimitConfig),
      ).void
    end
    def initialize(pull_request:, current_user:, thread_ids: [], limit_config: nil)
      @pull_request = pull_request
      @current_user = current_user
      @thread_ids = thread_ids
      @limit_config = limit_config
    end

    sig { returns(ReviewMenuData) }
    def load
      ReviewMenuData.new(
        viewer_has_violated_push_policy: viewer_has_violated_push_policy,
        viewer_is_copilot_attributed: viewer_is_copilot_attributed,
        viewer_permission: viewer_permission,
        threads: load_threads,
      )
    end

    private

    sig { returns(T::Boolean) }
    def viewer_has_violated_push_policy
      return false unless @current_user

      with_database_error_fallback(fallback: false) do
        !!@pull_request.user_has_violated_push_rule?(@current_user)
      end
    end

    sig { returns(T::Boolean) }
    def viewer_is_copilot_attributed
      return false unless @current_user

      with_database_error_fallback(fallback: false) do
        !!@pull_request.is_copilot_co_author?(@current_user)
      end
    end

    sig { returns(ViewerPermission) }
    def viewer_permission
      return PERMISSION_FALLBACK unless @current_user

      with_database_error_fallback(fallback: PERMISSION_FALLBACK) do
        raw = @pull_request.repository&.role_based_access_level(@current_user)&.to_s&.upcase
        ViewerPermission.try_deserialize(raw) || PERMISSION_FALLBACK
      end
    end

    sig { returns(T::Array[PullRequests::PageData::Threads::Loader::PullRequestThreadData]) }
    def load_threads
      return [] if @thread_ids.empty? || @limit_config.nil?

      PullRequests::PageData::Threads::Loader.load_by_ids(
        current_user: @current_user,
        pull_request: @pull_request,
        limit_config: @limit_config,
        thread_ids: @thread_ids,
      )
    end
  end
end
