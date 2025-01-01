# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::MergeBox
  class MergeRequirementsLoader
    include GitHub::ResilienceMixin

    class MergeRequirementsData < T::Struct
      const :commit_author_email, String
      const :commit_message_body, T.nilable(String)
      const :commit_message_headline, T.nilable(String)
      const :state, Symbol
      const :conditions, T::Array[T::any(PullRequests::PageData::MergeBox::MergeRequirementsPayload::MergeConditionPayload, PullRequests::PageData::MergeBox::MergeRequirementsPayload::ConflictMergeConditionPayload)]
    end

    sig { returns(User) }
    attr_reader :viewer

    sig { returns(PullRequest) }
    attr_reader :pull_request

    sig { returns(Repository) }
    attr_reader :repository

    sig { returns(T.nilable(String)) }
    attr_reader :merge_action

    sig { returns(T.nilable(String)) }
    attr_reader :merge_method

    sig { returns(T::Boolean) }
    attr_reader :bypass_requirements

    sig do
      params(
        viewer: User,
        pull_request: PullRequest,
        repository: Repository,
        merge_action: T.nilable(String),
        merge_method: T.nilable(String),
        bypass_requirements: T::Boolean,
      ).returns(T.nilable(MergeRequirementsData))
    end
    def self.load(viewer:, pull_request:, repository:, merge_action:, merge_method:, bypass_requirements:)
      new(viewer:, pull_request:, repository:, merge_action:, merge_method:, bypass_requirements:).load
    end

    sig do params(viewer: User,
      pull_request: PullRequest,
      repository: Repository,
      merge_action: T.nilable(String),
      merge_method: T.nilable(String),
      bypass_requirements: T::Boolean).void
    end
    def initialize(viewer:, pull_request:, repository:, merge_action: nil, merge_method: nil, bypass_requirements: false)
      @viewer = viewer
      @pull_request = pull_request
      @repository = repository
      @merge_action = merge_action
      @merge_method = merge_method
      @bypass_requirements = bypass_requirements
    end

    sig { returns(String) }
    def commit_author_email
      if @merge_method == "MERGE"
        @pull_request.merge_commit_author_email(@viewer)
      elsif @merge_method == "SQUASH"
        @pull_request.squash_commit_author_email(@viewer)
      else
        @viewer.default_author_email(@repository) || @viewer.git_author_email
      end
    end

    sig { returns(T.nilable(MergeRequirementsData)) }
    def load
      #Do not load MergeRequirements if a pull request is merged or closed
      return if pull_request.closed? || pull_request.merged?
      merge_requirements = PullRequest::MergeRequirements.new(pull_request, merge_action, merge_method, bypass_requirements, viewer, skip_checks: viewer.feature_enabled?(:skip_checks_true))
      MergeRequirementsData.new(
        state: with_database_error_fallback(fallback: :unknown) { merge_requirements.state },
        conditions: merge_requirements.conditions.map(&:condition_payload),
        commit_author_email: commit_author_email,
        commit_message_headline: with_database_error_fallback(fallback: nil) { merge_requirements.commit_message_headline },
        commit_message_body: with_database_error_fallback(fallback: nil) { merge_requirements.commit_message_body }
      )
    end
  end
end
