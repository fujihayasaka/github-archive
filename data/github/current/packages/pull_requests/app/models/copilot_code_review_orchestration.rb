# typed: true
# frozen_string_literal: true
class CopilotCodeReviewOrchestration < ApplicationRecord::Domain::IssuesPullRequests
  include Orchestration
  extend T::Sig

  belongs_to :pull_request
  validates :pull_request_id, presence: true, unless: :skip_pull_request_id_validation

  protected def target_uniqueness_condition_on_start
    { repository_id: self.repository_id, pull_request_id: self.pull_request_id }
  end

  def self.base_orchestration
    CopilotCodeReviewOrchestration
  end

  def skip_pull_request_id_validation
    false
  end

  def skip_pull_request_review_comment_id_validation
    false
  end

  def actor
    return nil if data[:actor_id].blank?
    @actor ||= User.find_by(id: data[:actor_id])
  end

  def log_data(options = {})
    options
  end

  def failbot_data
    {}
  end

  sig { returns(PullRequest) }
  def pull_request!
    T.must(pull_request)
  end
end
