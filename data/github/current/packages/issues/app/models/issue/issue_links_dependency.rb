# typed: true
# frozen_string_literal: true

module Issue::IssueLinksDependency
  extend T::Helpers
  extend ActiveSupport::Concern
  include HierarchyHelper

  requires_ancestor { Issue }

  included do
    T.bind(self, T.class_of(Issue))

    has_many :target_issue_links, class_name: "IssueLink", foreign_key: "target_issue_id", inverse_of: :target_issue
    destroy_dependents_in_background :target_issue_links

    has_many :source_issue_links, class_name: "IssueLink", foreign_key: "source_issue_id", inverse_of: :source_issue
    destroy_dependents_in_background :source_issue_links

    has_many :tracked_issues,     -> { has_tracked_link.sorted_by_link_creation }, through: :source_issue_links, source: :target_issue
    has_many :tracked_in_issues,  -> { has_tracked_link.sorted_by_link_creation }, through: :target_issue_links, source: :source_issue

    scope :has_tracked_link,        -> { where("issue_links.link_type = ?", IssueLink.link_types[:track]) }
    scope :closed,                  -> { where(state: "closed") }
    scope :sorted_by_link_creation, -> { select("issues.*, issue_links.created_at").order("issue_links.created_at, issues.id") } # Vitess needs the `order` column included in `select`
  end

  def tracked_issues_count
    tracked_issues.pluck("id", "issue_links.created_at").size
  end

  def tracked_issues_progress
    return @tracked_issues_progress if defined?(@tracked_issues_progress)

    total = tracked_issues.load.size
    completed = tracked_issues.to_a.count { |x| x.state == "closed" }

    @tracked_issues_progress = { total: total, completed: completed }
  end

  def has_tracked_issues?
    self.source_issue_links.where(link_type: :track).any?
  end

  def displayable_tracking_issues_for(viewer:)
    raise ArgumentError, "`viewer` must be present" if !defined?(:viewer)

    prepare_for_display(issues: all_tracking_issues, viewer: viewer)
  end

  # Returns the number of all parents that the viewerr has access to
  def displayable_tracking_issues_count(viewer:)
    raise ArgumentError, "`viewer` must be present" if !defined?(:viewer)
    displayable_tracking_issues_for(viewer: viewer).count
  end

  # Returns the number of all parents, regardless of access rights
  def tracking_issues_total_count
    @tracking_issues_total_count ||= self.tracked_in_issues.size
  end

  def normalized_tracking_issues(viewer:, cap_filter: nil)
    raise ArgumentError, "`viewer` must be present" if !defined?(:viewer)
    return @normalized_tracking_issues if defined?(@normalized_tracking_issues)

    issues_graph_normalized = TasklistBlocks::Redactor
      .new(viewer: viewer, issues: parent_issues, cap_filter: cap_filter, options: { exclude_redacted_issues: true })
      .issues
      .map { |issue| T.unsafe(issue).to_issue_link }
      .map { |issue_link| issue_link.serialize.symbolize_keys }

    model_normalized = displayable_tracking_issues_for(viewer: viewer)
      # de-duplicate any issues already returned from issues-graph
      .select { |issue| !issues_graph_normalized.any? { |hierarchy_issue| issue.id == hierarchy_issue[:issue_id] } }
      .map do |tracked_issue|
      {
        issue_id: tracked_issue.id,
        owner: tracked_issue.repository.owner_display_login,
        repository: tracked_issue.repository.name,
        issue_title: tracked_issue.title,
        issue_number: tracked_issue.number,
        issue_url: tracked_issue.url,
        issue_state: tracked_issue.state,
        issue_state_reason: tracked_issue.state_reason,
      }
    end

    @normalized_tracking_issues = issues_graph_normalized + model_normalized
  end

  def normalized_tracking_issues_count(viewer:)
    raise ArgumentError, "`viewer` must be present" if !defined?(:viewer)
    normalized_tracking_issues(viewer: viewer).count
  end

  # Add subtask relationship between this issue and target_issue
  def track_issue(target_issue, actor, new_target_issue = false, backfill = false)
    return if self.editable_by?(actor) == false && backfill == false
    return if target_issue.readable_by?(actor) == false && backfill == false

    issue_link = IssueLink.new(
      source_issue_id: self.id,
      target_issue_id: target_issue.id,
      source_repository_id: T.must(repository).id,
      target_repository_id: target_issue.repository.id,
      actor_id: actor.id,
      link_type: :track
    )

    if issue_link.save
      log_issue_link_create_to_hydro(issue_link: issue_link, actor: actor, new_target_issue: new_target_issue)
    else
      errors.add(:tracked_create, "Failed to create a tracked issue for #{target_issue.nwo_reference(repository)}")
    end

    issue_link
  end

  ## This method creates tracked issues in a single batch using as little SQL queries as possible
  ## It validates the input array:
  ## 1. Actor's write permission is checked for source repo
  ## 1. Actor's read permission is checked for the target repo
  ## 2. Self references are forbidden
  ## 3. PR references are forbidden
  def track_issues_batch(target_issues, actor, backfill = false)
    return unless target_issues.present?
    return unless target_issues.size > 0

    if backfill
      backfill_issues(target_issues, actor)
    else
      add_permitted_issues(target_issues, actor)
    end
  end

  # Deletes tracking relationship by removing an existing issue link between this issue and target_issue
  # Does not destroy the target_issue object
  def stop_tracking(target_issue, actor)
    begin
      issue_link = IssueLink.find_by(
        source_issue_id: self.id,
        target_issue_id: target_issue.id,
        link_type: :track
      )

      if self.editable_by?(actor)
        if T.must(issue_link).destroy
          log_issue_link_delete_to_hydro(issue_link: issue_link, actor: actor)
        else
          errors.add(:unable_to_delete, "Failed to stop tracking #{target_issue}")
        end
      else
        errors.add(:no_permissions_to_delete, "No permissions to stop tracking #{target_issue.nwo_reference(repository)}")
      end
      issue_link
    rescue ActiveRecord::RecordNotFound => e
      errors.add(:unable_to_find, "Could not find a tracked issue #{target_issue.nwo_reference(repository)}")
    end
  end

  def stop_tracking_batch(target_issues, actor)
    return unless target_issues.present?
    return unless target_issues.size > 0
    return unless self.editable_by?(actor)

    all_issue_links = T.let(nil, T.nilable(Arel::Nodes::Node))
    xrepo_issue_links_number = 0

    target_issues.each do |issue|
      clause = IssueLink.where(source_issue_id: self.id, target_issue_id: issue.id, link_type: IssueLink.link_types[:track]).arel.constraints.first
      if all_issue_links.nil?
        all_issue_links = clause
      else
        all_issue_links = all_issue_links.or(clause)
      end

      if issue.repository_id != self.repository_id
        xrepo_issue_links_number = xrepo_issue_links_number + 1
      end
    end

    # The delete_all method deletes this batch of issue_links records with
    # one query, skipping validations and callbacks, and silently ignoring
    # rows that violate unique constraints
    IssueLink.where(all_issue_links).delete_all
    log_issue_link_batch_delete_to_hydro(actor: actor, source_repository: self.repository, source_issue: self, total_issue_links: target_issues.size, xrepo_issue_links: xrepo_issue_links_number)
  end

  def toggle_tracked_issue_state(target_issue, actor)
    unless target_issue.toggle(actor)
      errors.add(:tracked_update, "Failed to update the tracked issue for #{target_issue.nwo_reference(repository)}")
    end
  end

  private

  def all_tracking_issues
    @all_tracking_issues ||= self.tracked_in_issues.includes(:repository, repository: :owner)
  end

  def all_tracked_issues
    @all_tracked_issues ||= self.tracked_issues.includes(:repository, repository: :owner)
  end

  def prepare_for_display(issues:, viewer:)
    # We are displaying only the issues for which current user has edit permissions.
    # Then we group them primarily by state and then by the order they were added.
    # To achieve this, we first group by state and then reverse sort the Map by keys.
    # Finally we flat-map sorted key-value pairs to get an Array of issues.

    issues_by_state = async_filter_readable(issues: issues, viewer: viewer).sync.group_by { |p| p.state.to_sym }
    issues_by_state.sort.reverse.flat_map { |_k, v| v }
  end

  def async_filter_readable(issues:, viewer:)
    readable_issues_promises = issues.map do |issue|
      issue.async_readable_by?(viewer).then do |readable|
        next issue if readable
      end
    end
    Promise.all(readable_issues_promises).then { |readable_issues| readable_issues.compact }
  end

  def log_issue_link_create_to_hydro(issue_link:, actor:, new_target_issue: false)
    GlobalInstrumenter.instrument(
      "issue_links.create",
      {
        actor: actor,
        source_repository: issue_link.source_repository,
        source_issue: issue_link.source_issue,
        target_repository: issue_link.target_repository,
        target_issue: issue_link.target_issue,
        new_target_issue: new_target_issue,
        link_type: :subtask # this is left as SUBTASK to leave protobuf definitions as is
      },
    )
  end

  def log_issue_link_delete_to_hydro(issue_link:, actor:)
    GlobalInstrumenter.instrument(
      "issue_links.delete",
      {
        actor: actor,
        source_repository: issue_link.source_repository,
        source_issue: issue_link.source_issue,
        target_repository: issue_link.target_repository,
        target_issue: issue_link.target_issue,
        link_type: :subtask # this is left as SUBTASK to leave protobuf definitions as is
      },
    )
  end

  def log_issue_link_batch_create_to_hydro(actor:, source_repository:, source_issue:, total_issue_links:, xrepo_issue_links:)
    GlobalInstrumenter.instrument(
      "issue_link_batch.create",
      {
        actor: actor,
        source_repository: source_repository,
        source_issue: source_issue,
        total_issue_links: total_issue_links,
        xrepo_issue_links: xrepo_issue_links,
        link_type: :subtask # this is left as SUBTASK to leave protobuf definitions as is
      },
    )
  end

  def log_issue_link_batch_delete_to_hydro(actor:, source_repository:, source_issue:, total_issue_links:, xrepo_issue_links:)
    GlobalInstrumenter.instrument(
      "issue_link_batch.delete",
      {
        actor: actor,
        source_repository: source_repository,
        source_issue: source_issue,
        total_issue_links: total_issue_links,
        xrepo_issue_links: xrepo_issue_links,
        link_type: :subtask # this is left as SUBTASK to leave protobuf definitions as is
      },
    )
  end

  def add_permitted_issues(target_issues, actor)
    return unless self.editable_by?(actor)

    permissions = target_issues.map do |issue|
      issue.async_repository.then do |repository|
        repository.async_readable_by?(actor)
      end
    end

    # fetch all permissions in a single query
    permissions = Promise.all(permissions).sync

    created_at = Time.now.utc
    xrepo_issue_links_number = 0
    changes = target_issues.each_with_index.reduce(Array.new) do |memo, (issue, index)|

      # filter out pull requests
      next memo if issue&.pull_request_id?
      # filter out self references
      next memo if issue == self
      # filter out issues without read permissions for the current user
      next memo unless permissions[index]

      if issue.repository_id != self.repository_id
        xrepo_issue_links_number += 1
      end

      memo.push({
        actor_id: actor.id,
        source_issue_id: self.id,
        target_issue_id: issue.id,
        source_repository_id: self.repository_id,
        target_repository_id: issue.repository_id,
        link_type: IssueLink.link_types[:track],
        created_at: created_at,
        updated_at: created_at })
    end
    return if changes.size == 0
    # The insert_all method creates this batch of issue_links records with
    # one query, skipping validations and callbacks, and silently ignoring
    # rows that violate unique constraints
    IssueLink.insert_all(changes)
    log_issue_link_batch_create_to_hydro(actor: actor, source_repository: self.repository, source_issue: self, total_issue_links: changes.length, xrepo_issue_links: xrepo_issue_links_number)
  end

  def backfill_issues(target_issues, actor)
    changes = target_issues.each_with_index.reduce(Array.new) do |memo, (issue, _index)|
      # filter out pull requests
      next memo if issue&.pull_request_id?
      # filter out self references
      next memo if issue == self

      memo.push({
        actor_id: actor.id,
        source_issue_id: self.id,
        target_issue_id: issue.id,
        source_repository_id: self.repository_id,
        target_repository_id: issue.repository_id,
        link_type: IssueLink.link_types[:track],
        created_at: created_at,
        updated_at: created_at })
    end
    return if changes.size == 0
    # The insert_all method creates this batch of issue_links records with
    # one query, skipping validations and callbacks, and silently ignoring
    # rows that violate unique constraints
    IssueLink.insert_all(changes)
  end
end
