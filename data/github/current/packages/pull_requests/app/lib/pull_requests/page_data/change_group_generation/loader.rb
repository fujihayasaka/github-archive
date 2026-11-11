# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::ChangeGroupGeneration
  class Loader
    include GitHub::Memoizer

    class Data < T::Struct
      const :can_access_change_groups, T::Boolean, default: false
      const :change_groups, T::Array[PullRequests::ChangeGroup]
      const :latest_change_group_orchestration, T.nilable(PullRequests::Orchestrations::MakeChangeGroups)
      const :change_group_generation_channel, String
    end

    sig { params(comparison: T.nilable(PullRequest::Comparison), current_user: T.nilable(User), pull_request: PullRequest).returns(Data) }
    def self.load(comparison:, current_user:, pull_request:)
      new(comparison:, current_user:, pull_request:).load
    end

    sig { params(comparison: T.nilable(PullRequest::Comparison), current_user: T.nilable(User), pull_request: PullRequest).void }
    def initialize(comparison:, current_user:, pull_request:)
      @comparison = comparison
      @current_user = current_user
      @pull_request = pull_request
      @repository = T.let(pull_request.repository, T.nilable(Repository))
    end

    sig { returns(Data) }
    def load
      Data.new(
        can_access_change_groups: can_access_change_groups?,
        change_groups: load_change_groups,
        latest_change_group_orchestration: load_latest_change_group_orchestration,
        change_group_generation_channel: GitHub::WebSocket::Channels.signed_pull_request_change_group_generation(@pull_request)
      )
    end

    private

    sig { returns(T::Boolean) }
    memoize def can_access_change_groups?
      access = PullRequests::Copilot::PullRequestGroupsAccess.new(actor: @current_user, current_repository: @repository)
      access.can_view_generated_groups?
    end

    sig { returns(T::Array[PullRequests::ChangeGroup]) }
    def load_change_groups
      return [] unless can_access_change_groups? && @comparison&.current?

      @pull_request.current_change_groups.order(priority: :desc).to_a
    end

    sig { returns(T.nilable(PullRequests::Orchestrations::MakeChangeGroups)) }
    def load_latest_change_group_orchestration
      return nil unless can_access_change_groups? && @comparison&.current?

      orchestration = PullRequests::Orchestrations::MakeChangeGroups
        .where(pull_request_id: @pull_request.id, repository_id: @repository&.id)
        .order(created_at: :desc)
        .first

      orchestration if orchestration&.current_for?(pull_request: @pull_request)
    end
  end
end
