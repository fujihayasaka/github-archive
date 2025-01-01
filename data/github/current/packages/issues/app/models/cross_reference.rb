# typed: true
# frozen_string_literal: true

# When a `Referrer` object mentions a `Referenceable` object, a
# `CrossReference` is created.
#
# The referrer is the source, the referenceable is the target, and the actor is
# the user that mentioned the target from the source.
class CrossReference < ApplicationRecord::Domain::IssuesPullRequests
  include Spam::Spammable
  include GitHub::Relay::GlobalIdentification
  include CrossReference::Prefillable

  VALID_TYPES = %w(
    Issue
    Discussion
    Team
    Milestone
  ).freeze

  belongs_to :source, polymorphic: true, required: true
  belongs_to :target, polymorphic: true, required: true
  belongs_to :actor, class_name: "User", required: true

  validates :target_id, uniqueness: { scope: [:source_id, :source_type, :target_type] }
  validates_inclusion_of :target_type, in: VALID_TYPES, message: "is not a valid target type"
  validates_inclusion_of :source_type, in: VALID_TYPES, message: "is not a valid source type"

  setup_spammable(:actor)

  # Looking to add more active record callbacks? We use `insert_all` in Referanceable.batch_record_references_from
  # Please make sure you ensure the changes are handled here as `insert_all` skips Active Record callbacks
  before_create :set_source_repository_id, :set_target_repository_id # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  # Scopes for filtering the referencing object type.
  scope :descending,  -> { order("created_at DESC") }
  scope :issues,      -> { where(source_type: "Issue") }
  scope :discussions, -> { where(source_type: "Discussion") }
  scope :milestones,  -> { where(source_type: "Milestone") }
  scope :teams,       -> { where(source_type: "Team") }

  scope :referencing, -> (type) { where(target_type: type) }

  # Return a new Relation that filters out `CrossReference`s
  # which target an issue and repo that no longer exists.
  scope :with_valid_target_issue, -> {
    joins(<<~SQL)
      INNER JOIN `issues` `target_issues` ON
        `cross_references`.`target_repository_id` = `target_issues`.`repository_id` AND
        `cross_references`.`target_id` = `target_issues`.`id` AND
        `cross_references`.`target_type` = 'Issue'
    SQL
  }

  # Return a new Relation that filters out `CrossReference`
  # which were made from an issue and repo that no longer exists.
  scope :with_valid_source_issue, -> {
    joins(<<~SQL)
      INNER JOIN `issues` `source_issues` ON
        `cross_references`.`source_repository_id` = `source_issues`.`repository_id` AND
        `cross_references`.`source_id` = `source_issues`.`id` AND
        `cross_references`.`source_type` = 'Issue'
    SQL
  }

  scope :with_spammy_source_issues_hidden_for, ->(viewer) {
    return if !GitHub.spamminess_check_enabled? || viewer&.site_admin?

    if viewer
      with_valid_source_issue.where("`source_issues`.`user_hidden` = false OR `source_issues`.`user_id` = ?", viewer.id)
    else
      with_valid_source_issue.where("`source_issues`.`user_hidden` = false")
    end
  }

  # Return a new Relation that selects only `CrossReference`s
  # that were made before the target issue got locked.
  scope :created_before_target_conversation_was_locked, -> {
    with_valid_target_issue.
    where(<<~SQL)
     `target_issues`.`locked_at` IS NULL OR (`cross_references`.`created_at` < `target_issues`.`locked_at`)
    SQL
  }

  # Return records based on source
  def self.from(source)
    where(source: source)
  end

  # See IssueTimeline
  def timeline_sort_by
    [created_at]
  end

  def referenced_at
    attributes["referenced_at"] || created_at
  end

  def visible_to?(viewer)
    async_visible_to?(viewer).sync
  end

  def source_issue_or_pull_request
    return @source_issue_or_pull_request if defined? @source_issue_or_pull_request
    @source_issue_or_pull_request = async_source_issue_or_pull_request.sync
  end

  def async_source_issue_or_pull_request
    async_source.then do |issue|
      if issue&.pull_request_id
        issue.async_pull_request
      else
        issue
      end
    end
  end

  def target_issue_or_pull_request
    return @target_issue_or_pull_request if defined? @target_issue_or_pull_request
    @target_issue_or_pull_request = async_target_issue_or_pull_request.sync
  end

  def async_target_issue_or_pull_request
    async_target.then do |issue|
      if issue&.pull_request_id
        issue.async_pull_request
      else
        issue
      end
    end
  end

  # Public: Will the source close the target when merged?
  #
  # Returns a boolean
  def async_will_close_target?
    Promise.all([
      async_source_issue_or_pull_request,
      async_target_issue_or_pull_request,
    ]).then do |source, target|
      # Only open PRs can close targets
      next false unless source&.open? && target&.open?
      next false unless source.is_a?(PullRequest)
      next false if target.is_a?(PullRequest)

      source.async_repository.then do |source_repo|
        next false unless source_repo
        target.async_close_issue_references.then do
          Promise.resolve(target.may_be_closed_by?(source.id))
        end
      end
    end
  end

  def cross_repository?
    return unless source && target
    source.repository_id != target.repository_id
  end

  # Public: Is this a reference to an issue/PR on a different repository from the one where it was made?
  #
  # Returns a boolean
  def async_cross_repository?
    Promise.all([
      async_source,
      async_target,
    ]).then do |source, target|
      next unless source && target
      source.repository_id != target.repository_id
    end
  end

  def path_uri
    return @path_uri if defined?(@path_uri)
    @path_uri = async_path_uri.sync
  end

  def async_path_uri
    Promise.all([
      async_source,
      async_target,
    ]).then do |source, target|
      next unless source && target
      target.async_path_uri.then do |path|
        noun = source.pull_request_id ? "pullrequest" : "issue"
        event_path = path.dup
        event_path.fragment = "ref-#{noun}-#{source.id}"
        event_path
      end
    end
  end

  def async_visible_to?(viewer)
    async_source.then do |source|
      # This check and the next are needed because we have broken associations
      # (https://github.com/github/github/pull/74589#discussion_r122992323)
      next false unless source

      source.async_repository.then do |repository|
        next false unless repository

        if source.is_a?(Issue)
          next false if !repository.has_issues? && !source.pull_request_id
          source.async_readable_by?(viewer)
        elsif source.is_a?(Discussion)
          source.async_readable_by?(viewer)
        else
          # This code is verified dead (see the previous change), but since the
          # class is polymorphic, we'll keep it here to (🤞) handle non-issue cases.
          repository.async_readable_by(viewer)
        end
      end
    end
  end

  def self.oauth_app_policy_violating_repo_ids(viewer)
    return [] unless viewer&.using_oauth_application?
    Repository.oauth_app_policy_violated_repository_ids(
      # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
      repository_ids: viewer.associated_repository_ids(include_oauth_restriction: false),
      # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
      repository_scope: Repository.private_scope,
      app: viewer.oauth_application,
    )
  end

  def platform_type_name
    "CrossReferencedEvent"
  end

  private

  def set_source_repository_id
    # all sources have the 'repository_id' method.
    self.source_repository_id = self.source&.repository_id
  end

  def set_target_repository_id
    # not all targets have the 'repository_id' method. This due to the polymorphic relationship to 'target'.
    self.target_repository_id = self.target&.repository_id if self.target&.respond_to? :repository_id
  end
end
