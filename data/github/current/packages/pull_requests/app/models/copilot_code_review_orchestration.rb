# typed: true
# frozen_string_literal: true

class CopilotCodeReviewOrchestration < ApplicationRecord::Domain::IssuesPullRequests
  include Orchestration
  include RepositoryOrchestrationBase

  belongs_to :pull_request
  validates :pull_request_id, presence: true, unless: :skip_pull_request_id_validation

  protected def target_uniqueness_condition_on_start
    { repository_id: self.repository_id, pull_request_id: self.pull_request_id }
  end

  def self.base_orchestration
    CopilotCodeReviewOrchestration
  end

  def self.log_prefix
    "gh.copilot_code_review"
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

  sig { void }
  def validate_no_duplicates
    if repository_id.present?
      existing_id = self.class.active.where(type: self.class, repository_id: repository_id).pluck(:id).first
      if existing_id.present?
        errors.add(:base, :duplicate, message: "orchestration in progress #{existing_id}")
      end
    end
  end
end
