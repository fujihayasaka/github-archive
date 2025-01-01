# typed: true
# frozen_string_literal: true

class RepositoryIssueType < ApplicationRecord::Domain::IssuesPullRequests
  include GitHub::UTF8
  include GitHub::Validations
  include GitHub::BatchedScope

  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain legacy_return_type: true
  belongs_to :issue_type, inverse_of: :issues

  validates_presence_of :repository, :issue_type
  validates_inclusion_of :enabled, in: [true, false], message: "can't be blank"
  validates :issue_type, uniqueness: { scope: :repository }
  validate :ensure_organization_issue_type_enabled
  validate :ensure_repository_owned_by_issue_type_owner, on: [:create, :update]

  after_commit :reindex_issues, on: [:create, :update, :destroy] # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_hydro_create_event, on: :create # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_hydro_update_event, on: :update # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_hydro_destroy_event, on: :destroy # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  private

  sig { void }
  def reindex_issues
    # issue type availability on issues is determined by pressence or complete absence of disabled repository_issue_types
    should_update = if transaction_include_any_action?([:update])
      self.previous_changes["enabled"].present?
    elsif transaction_include_any_action?([:create, :destroy])
      true
    else
      false
    end

    # reindex all issue types when enabling/disabling issue types for a repo
    # loading issue_types from DB through owner relation to avoid AR query caching
    raw_issue_types = self.repository&.owner&.reload&.issue_types || []
    raw_issue_types.each do |issue_type|
      Issues::ReindexIssuesForAssociationJob.enqueue(:issue_type, issue_type.id, {
        # using sharding options to limit reindexing the repo being enable/disabled
        sharding_key: :repository_id,
        sharding_key_value: T.must(self.repository).id
      })
    end if should_update
  end

  sig { void }
  def ensure_repository_owned_by_issue_type_owner
    return if repository.nil? || issue_type.nil?
    unless repository&.owner == issue_type&.owner
      errors.add(:repository, "must be owned by issue type owner")
    end
  end

  sig { void }
  def ensure_organization_issue_type_enabled
    # Don't error if the user is disabling at the repo level an org level disabled issue type
    return if issue_type&.enabled? || !enabled

    errors.add(:issue_type, "must exist and be enabled by the issue type owner")
  end

  def modifying_user
    User.find_by(id: GitHub.context[:actor_id]) || User.ghost
  end

  def instrument_hydro_create_event
    GlobalInstrumenter.instrument "repository_issue_type.create", {
      actor: modifying_user,
      repository: repository,
      issue_type: issue_type,
      enabled: enabled?,
    }
  end

  def instrument_hydro_update_event
    GlobalInstrumenter.instrument "repository_issue_type.update", {
      actor: modifying_user,
      repository: repository,
      issue_type: issue_type,
      enabled: enabled?,
    }
  end

  def instrument_hydro_destroy_event
    GlobalInstrumenter.instrument "repository_issue_type.destroy", {
      actor: modifying_user,
      repository: repository,
      issue_type: issue_type,
      enabled: enabled?,
    }
  end
end
