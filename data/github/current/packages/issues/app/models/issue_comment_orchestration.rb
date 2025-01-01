# typed: true
# frozen_string_literal: true

class IssueCommentOrchestration < ApplicationRecord::Domain::IssuesPullRequests
  include Orchestration
  include RepositoryOrchestrationBase

  belongs_to :issue_comment
  belongs_to :issue
  validates :issue_comment_id, presence: true, unless: :skip_issue_comment_id_validation
  validates :issue_id, presence: true, unless: :skip_issue_id_validation

  protected def target_uniqueness_condition_on_start; end

  def self.base_orchestration
    IssueCommentOrchestration
  end

  def self.job_class
    IssueCommentOrchestrationJob
  end

  def self.log_prefix
    "gh.issue_comment"
  end

  def skip_issue_id_validation
    false
  end

  def skip_issue_comment_id_validation
    false
  end

  def validate_no_duplicates
    if issue_comment.present?
      existing_id = self.class.active.where(type: self.class, issue_comment_id: T.must(issue_comment_id), issue_id: T.must(issue_id), repository_id: T.must(repository_id)).pluck(:id).first
      if existing_id.present?
        errors.add(:base, :duplicate, message: "orchestration in progress #{existing_id}")
      end
    end
  end

  def log_data(options = {})
    {
      "code.namespace" => self.class.name,
      "gh.issue.id" => issue_id,
      "gh.issue_comment.id" => issue_comment_id,
      "gh.issue_comment.orchestration.id" => id,
      "gh.issue_comment.orchestration.type" => type,
      "gh.issue_comment.orchestration.state" => state,
      "gh.issue_comment.orchestration.step_name" => step_name,
      "gh.issue_comment.orchestration.attempts" => attempts,
      "gh.issue_comment.orchestration.data" => data,
      "gh.issue_comment.orchestration.error_message" => error_message,
      "gh.issue_comment.orchestration.initiated_by" => self.class.initiated_by,
      "gh.issue_comment.orchestration.uses_domain" => uses_domain?,
      "gh.repo.id" => repository_id,
      "gh.actor.id" => data[:actor_id],
      "gh.request_id" => GitHub.context[:request_id],
    }.merge(options)
  end

  def failbot_data
    {
      "gh.repo.id" => repository_id,
      "gh.issue.id" => issue_id,
      "gh.issue_comment.id" => issue_comment_id,
      "gh.issue_comment.orchestration.id" => id,
      "gh.issue_comment.orchestration.step_name" => step_name,
      "gh.issue_comment.orchestration.type" => type
    }
  end

  def datadog_tags
    ["uses_domain:#{uses_domain?}"]
  end

  def build_hydro_event_message
    self.class.build_hydro_event_message(repository_id, issue_id, issue_comment_id)
  end

  def self.build_hydro_event_message(repository_id, issue_id, issue_comment_id)
    message = {
      repository_id: repository_id,
      issue_id: issue_id,
      issue_comment_id: issue_comment_id,
      request_id: GitHub.context[:request_id],
    }
  end

  sig do
    params(
      comment: IssueComment,
      actor: T.nilable(User),
      uses_domain: T::Boolean,
    ).returns(CreateIssueCommentOrchestration)
  end
  def self.create_issue_comment!(comment:, actor:, uses_domain: false)
    data = {
      actor_id: actor&.id,
      issue_transfer: comment.issue_transfer?,
      importing: comment.importing?,
      issue_previous_changes_empty: comment.issue&.previous_changes.empty?,
      skip_touch_issue: should_skip_touch_issue(comment),
      uses_domain: uses_domain,
    }.compact_blank

    CreateIssueCommentOrchestration.create!(
      repository: comment.repository,
      issue: comment.issue,
      issue_comment: comment,
      data: data
    )
  end

  sig do
    params(
      comment: IssueComment,
      actor: T.nilable(User),
      uses_domain: T::Boolean,
    ).returns(UpdateIssueCommentOrchestration)
  end
  def self.update_issue_comment!(comment:, actor:, uses_domain: false)
    data = {
      actor_id: actor&.id,
      skip_touch_issue: should_skip_touch_issue(comment),
      uses_domain: uses_domain,
    }.compact_blank

    UpdateIssueCommentOrchestration.create!(
      repository: comment.repository,
      issue: comment.issue,
      issue_comment: comment,
      data: data
    )
  end

  sig do
    params(
      comment: IssueComment,
      actor: T.nilable(User),
      uses_domain: T::Boolean,
    ).returns(DeleteIssueCommentOrchestration)
  end
  def self.delete_issue_comment!(comment:, actor:, uses_domain: false)
    data = {
      actor_id: actor&.id,
      skip_touch_issue: should_skip_touch_issue(comment),
      uses_domain: uses_domain,
    }.compact_blank

    DeleteIssueCommentOrchestration.create!(
      repository_id: comment.repository_id,
      issue_id: comment.issue_id,
      issue_comment: comment,
      data: data
    )
  end

  sig { params(comment: IssueComment).returns(T::Boolean) }
  def self.should_skip_touch_issue(comment)
    # if previous_changes is not empty it means the issue was already updated in the same transaction
    !!comment.issue&.previous_changes.present?
  end

  sig { returns(T.nilable(User)) }
  def actor
    return nil if data[:actor_id].blank?
    @actor ||= User.find_by(id: data[:actor_id])
  end

  sig { returns(T::Boolean) }
  def uses_domain?
    !!data[:uses_domain]
  end

  sig { returns(T::Boolean) }
  def skip_touch_issue?
    !!data[:skip_touch_issue]
  end

  def self.initiated_by
    GitHub.context[:from].presence || GitHub.context[:job].presence || "unknown"
  end
end
