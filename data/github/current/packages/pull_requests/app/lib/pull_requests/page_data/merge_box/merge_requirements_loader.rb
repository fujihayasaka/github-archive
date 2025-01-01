# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::MergeBox
  class MergeRequirementsLoader
    extend T::Sig
    include GitHub::ResilienceMixin

    class MergeRequirementsData < T::Struct
      const :commit_author, String
      const :commit_message_body, String
      const :commit_message_headline, String
      const :state, Symbol
      const :conditions, T::Array[T::any(PullRequests::PageData::MergeBox::MergeRequirementsPayload::MergeConditionPayload, PullRequests::PageData::MergeBox::MergeRequirementsPayload::ConflictMergeConditionPayload)]
    end

    sig { returns(User) }
    attr_reader :viewer

    sig { returns(PullRequest) }
    attr_reader :pull_request

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
        merge_action: T.nilable(String),
        merge_method: T.nilable(String),
        bypass_requirements: T::Boolean
      ).returns(T.nilable(MergeRequirementsData))
    end
    def self.load(viewer:, pull_request:, merge_action:, merge_method:, bypass_requirements:)
      new(viewer:, pull_request:,  merge_action:, merge_method:, bypass_requirements:).load
    end

    sig do params(viewer: User,
      pull_request: PullRequest,
      merge_action: T.nilable(String),
      merge_method: T.nilable(String),
      bypass_requirements: T::Boolean).void
    end
    def initialize(viewer:, pull_request:, merge_action: nil, merge_method: nil, bypass_requirements: false)
      @viewer = viewer
      @pull_request = pull_request
      @merge_action = merge_action
      @merge_method = merge_method
      @bypass_requirements = bypass_requirements
    end

    sig { returns(T.nilable(MergeRequirementsData)) }
    def load
      #Do not load MergeRequirements if a pull request is merged or closed
      return if pull_request.closed? || pull_request.merged?

      merge_requirements = PullRequest::MergeRequirements.new(pull_request, merge_action, merge_method, bypass_requirements, viewer)
      MergeRequirementsData.new(
        state: with_database_error_fallback(fallback: :unknown) { merge_requirements.state },
        conditions: merge_requirements.conditions.map(&:condition_payload),
        commit_author: merge_requirements.commit_author,
        commit_message_headline: with_database_error_fallback(fallback: "") { merge_requirements.commit_message_headline },
        commit_message_body: with_database_error_fallback(fallback: "") { merge_requirements.commit_message_body }
      )
    end
  end
end
