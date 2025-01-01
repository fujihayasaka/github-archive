# typed: true
# frozen_string_literal: true
class PullRequestOrchestration < ApplicationRecord::Domain::IssuesPullRequests
  include GitHub::Memoizer
  include Orchestration
  include PullRequests::IOrchestration
  extend T::Sig

  belongs_to :pull_request
  validates :pull_request_id, presence: true

  sig { returns(T::Hash[Symbol, T.nilable(Integer)]) }
  protected def target_uniqueness_condition_on_start
    { repository_id: self.repository_id, pull_request_id: self.pull_request_id }
  end

  sig { returns(T.class_of(PullRequestOrchestration)) }
  def self.base_orchestration
    PullRequestOrchestration
  end

  sig { returns(T.class_of(PullRequestOrchestrationJob)) }
  def self.job_class
    PullRequestOrchestrationJob
  end

  sig { void }
  def validate_no_duplicates
    # TODO(dzader): consider adding a unique index on repo_id,pr_id,in_progress_state to ensure we only ever have one orchestration in progress
    if self.class.active.where(type: self.class, repository_id: repository_id, pull_request_id: pull_request_id).exists?
      errors.add(:base, :duplicate, message: duplicate_orchestration_error_message)
    end
  end

  sig { params(options: Hash).returns(Hash) }
  def log_data(options = {})
    {
      "code.namespace" => self.class.name,
      "gh.pull_request.id" => pull_request_id,
      "gh.pull_request.orchestration.id" => id,
      "gh.pull_request.orchestration.type" => type,
      "gh.pull_request.orchestration.state" => state,
      "gh.pull_request.orchestration.step_name" => step_name,
      "gh.pull_request.orchestration.attempts" => attempts,
      "gh.pull_request.orchestration.data" => data,
      "gh.repo.id" => repository_id,
      "gh.actor.id" => data[:actor_id],
      "gh.request_id" => GitHub.context[:request_id],
    }.merge(options)
  end

  sig { returns(Hash) }
  def failbot_data
    {
      "gh.repo.id" => repository_id,
      "gh.pull_request.id" => pull_request_id,
      "gh.pull_request.orchestration.id" => id,
      "gh.pull_request.orchestration.step_name" => step_name,
      "gh.pull_request.orchestration.type" => type
    }
  end

  sig { returns(T.nilable(User)) }
  memoize def user
    User.find_by(id: data[:user_id])
  end

  private

  sig { returns(String) }
  def duplicate_orchestration_error_message
    "orchestration in progress"
  end
end
