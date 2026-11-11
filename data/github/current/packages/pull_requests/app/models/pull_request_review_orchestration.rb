# typed: true
# frozen_string_literal: true

class PullRequestReviewOrchestration < ApplicationRecord::Domain::IssuesPullRequests
  include Orchestration
  include RepositoryOrchestrationBase

  extend T::Helpers

  # Potential return value from `step` DSL. Allows for halting of execution of the orchestration.
  StepTuple = T.type_alias { T.nilable([Symbol, String]) }

  belongs_to :pull_request
  belongs_to :pull_request_review
  validates :pull_request_id, presence: true
  validates :pull_request_review_id, presence: true

  protected def target_uniqueness_condition_on_start; end

  def self.base_orchestration
    PullRequestReviewOrchestration
  end

  def self.job_class
    PullRequestOrchestrationJob
  end

  def self.log_prefix
    "gh.pull_request_review"
  end

  def validate_no_duplicates; end

  def log_data(options = {})
    {
      "code.namespace" => self.class.name,
      "gh.pull_request.id" => pull_request_id,
      "gh.pull_request_review.id" => pull_request_review_id,
      "gh.pull_request_review.orchestration.id" => id,
      "gh.pull_request_review.orchestration.type" => type,
      "gh.pull_request_review.orchestration.state" => state,
      "gh.pull_request_review.orchestration.step_name" => step_name,
      "gh.pull_request_review.orchestration.attempts" => attempts,
      "gh.pull_request_review.orchestration.data" => data,
      "gh.repo.id" => repository_id,
      "gh.actor.id" => data[:actor_id],
      "gh.request_id" => GitHub.context[:request_id],
    }.merge(options)
  end

  def failbot_data
    {
      "gh.repo.id" => repository_id,
      "gh.pull_request.id" => pull_request_id,
      "gh.pull_request_review.id" => pull_request_review_id,
      "gh.pull_request_review.orchestration.id" => id,
      "gh.pull_request_review.orchestration.step_name" => step_name,
      "gh.pull_request_review.orchestration.type" => type
    }
  end

  sig { returns(T.nilable(User)) }
  def actor
    return nil if data[:actor_id].blank?
    @actor ||= User.find_by(id: data[:actor_id])
  end

  def self.initiated_by
    GitHub.context[:from].presence || GitHub.context[:job].presence || "unknown"
  end
end
