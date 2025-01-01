# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::MergeBox
  class MergeRequirementsLoader
    include GitHub::ResilienceMixin

    class MergeRequirementsData < T::Struct
      const :commit_author_email, T.nilable(String)
      const :commit_message_body, T.nilable(String)
      const :commit_message_headline, T.nilable(String)
      const :possible_commit_author_emails, T::Array[String]
      const :state, Symbol
      const :conditions, T::Array[T::any(PullRequests::PageData::MergeBox::MergeRequirementsPayload::GenericMergeConditionPayload, PullRequests::PageData::MergeBox::MergeRequirementsPayload::ConflictMergeConditionPayload, PullRequests::PageData::MergeBox::MergeRequirementsPayload::RepositoryRulesMergeConditionPayload, PullRequests::PageData::MergeBox::MergeRequirementsPayload::MergeConditionWithSubConditionsPayload)]
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


    sig { returns(T.nilable(MergeRequirementsData)) }
    def load
      #Do not load MergeRequirements if a pull request is merged or closed
      return if pull_request.closed? || pull_request.merged?
      merge_requirements = PullRequest::MergeRequirements.new(pull_request, merge_action, merge_method, bypass_requirements, viewer, skip_checks: viewer.feature_flag_enabled?(:skip_checks_true, default: false))
      MergeRequirementsData.new(
        state: with_database_error_fallback(fallback: :unknown) { merge_requirements.state },
        conditions: merge_requirements.conditions.map(&:condition_payload),
        commit_author_email: commit_author_email(merge_requirements),
        commit_message_headline: with_database_error_fallback(fallback: nil) { merge_requirements.commit_message_headline },
        commit_message_body: with_database_error_fallback(fallback: nil) { merge_requirements.commit_message_body },
        possible_commit_author_emails: merge_requirements.possible_commit_author_emails
      )
    end

    private

    sig { params(merge_requirements: PullRequest::MergeRequirements).returns(T.nilable(String)) }
    def commit_author_email(merge_requirements)
      merge_requirements.default_commit_author_email
    rescue GitRPC::ObjectMissing
      viewer.git_author_email
    end
  end
end
