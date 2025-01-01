# typed: true
# frozen_string_literal: true

class SubIssue < ApplicationRecord::Domain::IssuesPullRequests
  include GitHub::Prioritizable
  include GitHub::Memoizer

  class MaximumHeightError < StandardError; end

  # These constants should be in sync with the client-side values found in ui/packages/sub-issues/utils/use-alert.ts
  MAXIMUM_HEIGHT = 7
  MAXIMUM_BREADTH = 100
  MAXIMUM_HEIGHT_MESSAGE = "You can’t add more than #{MAXIMUM_HEIGHT} layers of sub-issues. To add a sub-issue, remove a parent issue at any level."

  belongs_to :source, class_name: "Issue", primary_key: :id, foreign_key: :source_issue_id, inverse_of: :sub_issue_relations
  belongs_to :target, class_name: "Issue", primary_key: :id, foreign_key: :target_issue_id, inverse_of: :parent_issue_relation
  belongs_to :actor, class_name: "User", required: true

  before_validation :set_repository_id, on: :create
  validates :source_repository_id, presence: true, on: :create
  validates :source, presence: true

  validates :priority, uniqueness: { scope: :source_issue_id },
    numericality: {
      less_than_or_equal_to: GitHub::Prioritizable::MAX_PRIORITY_VALUE,
      greater_than_or_equal_to: 0,
    }
  prioritizable_by subject: :target, context: :source

  validate :issues_only
  validate :under_maximum_breadth
  validate :no_self_association
  validate :same_owner
  validate :no_duplicate_sub_issue, on: :create

  # skip_only_one_parent_validation is used when we are replacing the parent of a sub-issue
  validate :only_one_parent, on: :create, unless: :skip_only_one_parent_validation
  attr_accessor :skip_only_one_parent_validation

  validate :no_circular_reference, on: :create
  validate :no_parent_transfer_on_create, on: :create
  validate :no_parent_transfer_on_update, on: :update

  after_create :update_list_heights_on_create
  after_destroy :update_list_heights_on_destroy

  after_create :notify_related_issues
  after_destroy :notify_related_issues

  after_create_commit :instrument_creation
  after_destroy_commit :instrument_destruction

  after_commit :reindex_issues

  sig { returns(Issue::Authorizable) }
  def source_issue_authorizable
    Issue::Authorizable.new(source_issue_id, source_repository_id)
  end

  sig { void }
  def notify_subscribers
    if previous_changes["priority"] && source.present?
      T.must(source).notify_sub_issues_updated
    end
  end

  def readable_by?(actor)
    async_readable_by?(actor).sync
  end

  def async_readable_by?(actor)
    Promise.all([
      source&.async_readable_by?(actor),
      target&.async_readable_by?(actor)
    ]).then do |(source_readable, target_readable)|
      source_readable && target_readable
    end
  end

  sig { params(actor: User, skip_notify_sub_issues_updated: T::Boolean).void }
  def instrument_transfer_and_notify(actor, skip_notify_sub_issues_updated = false)
    GlobalInstrumenter.instrument("sub_issue.add", {
      actor:,
      source_issue_repository_id: source_repository_id,
      source_issue: source,
      target_issue: target,
      existing: true,
      transfer: true,
    })
    T.must(target).notify_parent_updated
    # When creating more than one sub-issue during transfer, we only want to notify that sub-issues have been updated once,
    # rather than once per sub-issue.
    unless skip_notify_sub_issues_updated
      T.must(source).notify_sub_issues_updated
    end
    reindex_issues
  end

  sig { void }
  private def notify_related_issues
    GitHub.dogstats.distribution_time("sub_issue.notify_related_issues.dist.time") do
      T.must(target).notify_parent_updated if source.present?
      T.must(source).notify_sub_issues_updated if source.present?
    end
  end

  sig { void }
  private def set_repository_id
    self.source_repository_id = T.must(source).repository_id
  end

  # Private: emit an event for Hydro to publish
  # Returns nothing
  sig { void }
  private def issues_only
    return unless target = self.target
    return unless source = self.source

    errors.add(:sub_issue, "may only be an issue") if target.pull_request?
    errors.add(:parent, "may only be an issue") if source.pull_request?
  end

  sig { void }
  private def under_maximum_breadth
    return unless source = self.source
    if source.sub_issue_relations.count >= MAXIMUM_BREADTH
      GitHub.dogstats.increment("sub_issue.maximum_breadth_hit")
      GitHub.logger.info(
        "Sub issue breadth limitation reached",
        "code.namespace": "SubIssue",
        "code.function": "under_maximum_breadth",
        "gh.source_issue.id": source.id,
        "gh.source_repo.id": source.repository_id,
        "gh.sub_issue.id": target_issue_id,
      )
      # This message is matched in ui/packages/sub-issues/utils/use-alert.ts to parse the limit to present a specific
      # message to the user. if the language here is changed, it should be changed there as well.
      errors.add(:parent, "cannot have more than #{MAXIMUM_BREADTH} sub-issues")
    end
  end

  sig { void }
  private def instrument_creation
    GitHub.dogstats.distribution_time("sub_issue.instrument_creation.dist.time") do
      # Instrument for webhooks and audit log
      if source && target
        GitHub.instrument("sub_issues.sub_issue_add", {
          parent_issue_id: source_issue_id,
          child_issue_id: target_issue_id,
          actor_id: GitHub.context[:actor_id],
          # for audit log
          issue: source,
          title: target&.title,
          repo: source&.repository,
          org: source&.repository&.organization,
        })
        # Instrument corresponding event for the parent issue
        GitHub.instrument("sub_issues.parent_issue_add", {
          parent_issue_id: source&.id,
          child_issue_id: target&.id,
          actor_id: GitHub.context[:actor_id],
          # for audit log
          issue: target,
          title: source&.title,
          repo: target&.repository,
          org: target&.repository&.organization,
        })
      end

      # Instrument Hydro event
      GlobalInstrumenter.instrument("sub_issue.add", {
        actor: safe_actor,
        source_issue_repository_id: source_repository_id,
        source_issue: source,
        target_issue: target,
        # If the ID just changed, then it is a new issue. We check both `id_previously_changed?` and `id_changed?` just
        # in case the ID was already persisted to the database.
        existing: !target&.id_previously_changed? && !target&.id_changed?,
        transfer: false,
      })
    end
  end

  sig { void }
  private def instrument_destruction
    GitHub.dogstats.distribution_time("sub_issue.instrument_destruction.dist.time") do
      # Instrument for webhooks and audit log
      # If either source or target are nil, it's likely because the parent or sub-issue was deleted.
      # In this case, we'll generate webhook events in the issue model on before_destroy and only emit audit log events here.
      GitHub.instrument("sub_issues.sub_issue_remove", {
        parent_issue_id: source_issue_id,
        child_issue_id: target_issue_id,
        actor_id: GitHub.context[:actor_id],
        # for audit log
        issue: source,
        title: target&.title,
        repo: source&.repository,
        org: source&.repository&.organization,
        audit_only: !source || !target,
      })

      GitHub.instrument("sub_issues.parent_issue_remove", {
        parent_issue_id: source_issue_id,
        child_issue_id: target_issue_id,
        actor_id: GitHub.context[:actor_id],
        # for audit log
        issue: target,
        title: source&.title,
        repo: target&.repository,
        org: target&.repository&.organization,
        audit_only: !source || !target,
      })

      # Instrument Hydro event
      GlobalInstrumenter.instrument("sub_issue.remove", {
        # actor here is not the same as the actor in the model. Actor is the one
        # removing the sub-issue, not the user who created the sub-issue.
        actor_id: GitHub.context[:actor_id],
        source_issue_repository_id: source_repository_id,
        source_issue: source,
        target_issue: target,
      })
    end
  end

  # Private: Get the actor for the event. If no actor is present, use the ghost
  # user.
  #
  # Returns a User
  sig { returns(User) }
  private def safe_actor = actor || User.ghost

  sig { void }
  private def no_self_association
    if source_issue_id == target_issue_id
      errors.add(:sub_issue, "cannot be the same as the parent issue")
    end
  end

  sig { void }
  private def same_owner
    return unless source = self.source
    return unless sub_issue = self.target
    return if source.repository_id == sub_issue.repository_id

    owner_one, owner_two = ActiveRecord::Base.connected_to(role: :reading) do
      Repository
      .where(id: [source.repository_id, sub_issue.repository_id])
      .pluck(:owner_id)
    end

    unless owner_one && owner_two && owner_one == owner_two
      GitHub.dogstats.increment("sub_issue.different_owners_attempted")
      errors.add(:sub_issue, "must have the same owner as the parent")
    end
  end

  sig { void }
  private def only_one_parent
    if SubIssue.where(target_issue_id:).exists?
      errors.add(:sub_issue, "may only have one parent")
    end
  end

  sig { void }
  private def no_circular_reference
    GitHub.dogstats.distribution_time("sub_issue.no_circular_reference.dist.time") do
      # If the added sub-issue has no children, then we have no need to check for circular references
      return unless SubIssue.exists?(source_issue_id: target_issue_id)

      next_id = source_issue_id
      while parent = SubIssue.find_by(target_issue_id: next_id) do
        if parent.source_issue_id == target_issue_id
          GitHub.dogstats.increment("sub_issue.circular_reference_attempted")
          errors.add(:sub_issue, "may not create a circular dependency")
          return
        end
        next_id = parent.source_issue_id
      end
    end
  end

  sig { void }
  private def no_duplicate_sub_issue
    if SubIssue.find_by(target_issue_id: target_issue_id, source_issue_id: source_issue_id).present?
      errors.add(:issue, "may not contain duplicate sub-issues")
    end
  end

  sig { void }
  private def no_parent_transfer_on_create
    no_parent_transfer(:create)
  end

  sig { void }
  private def no_parent_transfer_on_update
    no_parent_transfer(:update)
  end

  sig { params(action: Symbol).void }
  private def no_parent_transfer(action)
    return unless source = self.source

    if source.is_involved_in_current_transfer?
      GitHub.dogstats.increment("sub_issue.#{action}_during_transfer_attempted")
      errors.add(:source, "cannot #{action} sub-issues while a transfer is in-progress")
    end
  end

  sig { void }
  private def update_list_heights_on_create
    GitHub.dogstats.distribution_time("sub_issue.update_list_heights_on_create.dist.time") do
      # get the sub-issue list for the sub-issue that is being added, if it doesn't have a list, then it has a height of 0
      added_tree_height = SubIssueList.find_by(issue_id: target_issue_id)&.height || 0

      # increment this height by 1, which will theoretically be the height of the parent if it is the new tallest subtree
      potential_new_parent_tree_height = added_tree_height + 1

      # if the created height would create a height greater than 8, bail
      if potential_new_parent_tree_height > MAXIMUM_HEIGHT
        GitHub.dogstats.increment("sub_issue.maximum_height_hit")
        GitHub.logger.info(
          "Sub issue height limitation reached",
          "code.namespace": "SubIssue",
          "code.function": "update_list_heights_on_create",
          **shared_log_tags
        )
        errors.add(:sub_issue, MAXIMUM_HEIGHT_MESSAGE)
        raise MaximumHeightError.new(MAXIMUM_HEIGHT_MESSAGE)
      end

      source_list = SubIssueList.find_by(issue_id: source_issue_id)

      # if there is no source list, create one now (likely for first time parents)
      source_list ||= SubIssueList.build(issue: source, total: 1, completed: target&.closed? ? 1 : 0)

      update_heights_up_hierarchy_on_create(potential_new_parent_tree_height, source_list)
    end
  end

  sig { params(height_for_tree: Integer, source_list: SubIssueList).void }
  private def update_heights_up_hierarchy_on_create(height_for_tree, source_list)
    # lists array to keep track of lists which need to be saved
    updated_lists = T.let([], T::Array[SubIssueList])
    list_to_update = source_list

    # we only want to iterate up and update tree heights in the case that the height provided
    # is larger than the current height on the list, as the height represents the tallest branch
    while height_for_tree > list_to_update.height do
      if height_for_tree > MAXIMUM_HEIGHT
        GitHub.dogstats.increment("sub_issue.maximum_height_hit")
        GitHub.logger.info(
          "Sub issue height limitation reached",
          "code.namespace": "SubIssue",
          "code.function": "update_list_heights_on_create",
          **shared_log_tags
        )
        errors.add(:sub_issue, MAXIMUM_HEIGHT_MESSAGE)
        raise MaximumHeightError.new(MAXIMUM_HEIGHT_MESSAGE)
      end

      list_to_update.height = height_for_tree
      updated_lists << list_to_update

      # we can break early if the issue of this list has no parent
      parent_sub_issue = SubIssue.find_by(target_issue_id: list_to_update.issue_id)
      break unless parent_sub_issue

      # increment the height for the next iteration of this loop (i.e. for the list of this list's parent) and get
      # the next list for us to update
      height_for_tree = height_for_tree + 1
      next_list = SubIssueList.find_by(issue_id: parent_sub_issue.source_issue_id)

      # this is a case that we should never encounter (there is a parent issue, but it has no SubIssueList), but logging
      # here would help later debug
      if next_list.nil?
        GitHub.logger.info(
          "SubIssue#update_heights_up_hierarchy_on_create encountered an issue without a list",
          "code.namespace": "SubIssue",
          "code.function": "update_heights_up_hierarchy_on_create",
          **shared_log_tags
        )
        break
      end

      list_to_update = next_list
    end

    GitHub.dogstats.count("sub_issue.list_updates_made", updated_lists.count, tags: ["after:create"])
    # we can't better batch these saves, since we potentially created a new list in the caller
    updated_lists.each(&:save!)
  end

  sig { void }
  private def update_list_heights_on_destroy
    GitHub.dogstats.distribution_time("sub_issue.update_list_heights_on_destroy.dist.time") do
      # get the sub-issue list for the sub-issue that is being removed, if it doesn't have a list, then it has a height of 0
      removed_tree_height = SubIssueList.find_by(issue_id: target_issue_id)&.height || 0

      # get the list for our source
      source_list = SubIssueList.find_by(issue_id: source_issue_id)
      return unless source_list

      # we can return in the case that the height of the parent tree is taller than this removed tree + 1, because that
      # would mean that the removed tree did not belong to the longest path
      return if source_list.height > removed_tree_height + 1

      # if this isn't the case though, we need to find the largest height of all siblings to the removed tree
      all_sibling_ids = SubIssue.where(source_issue_id: source_issue_id).pluck(:target_issue_id)
      tallest_sibling_height = SubIssueList.where(issue_id: all_sibling_ids - [target_issue_id]).maximum(:height) || -1

      # there is no updating to be done if there is a sibling of same size or larger than the removed tree
      # (this is somewhat redundant to the check of the source_list.height, but this also allows us to check
      # if the new tallest subtree is of the same height)
      return if tallest_sibling_height >= removed_tree_height

      # if we've hit this point, we now know that the removed tree was the tallest of it's siblings, and therefore
      # we must proceed up the hierarchy, repeating this algorithm until we encounter one of the return situations above
      update_heights_up_hierarchy_after_destroy(tallest_sibling_height + 1, source_list)
    end
  end

  sig { params(potential_height: Integer, source_list: SubIssueList).void }
  private def update_heights_up_hierarchy_after_destroy(potential_height, source_list)
    updated_lists = T.let([], T::Array[SubIssueList])
    list_to_update = source_list

    # we should continue up the hierarchy until the height wouldn't change
    while potential_height != list_to_update.height do
      list_to_update.height = potential_height
      updated_lists << list_to_update

      # if there is no higher to go up on the tree, we stop here
      parent_sub_issue = SubIssue.find_by(target_issue_id: list_to_update.issue_id)
      break unless parent_sub_issue

      # find the tallest sibling, excluding the list_to_update, because it's correct height is in memory
      all_sibling_ids = SubIssue.where(source_issue_id: parent_sub_issue.source_issue_id).pluck(:target_issue_id) - [list_to_update.issue_id]
      tallest_sibling_height = SubIssueList.where(issue_id: all_sibling_ids).maximum(:height) || 0

      # compare the maximum queried height to the height we have locally updated to find the true max between the two
      tallest_sibling_height = [tallest_sibling_height, list_to_update.height].max

      # update the variables for the next iteration, with the tallest height incrementing as we go up the tree
      # once, and the list we're updating being the parent
      potential_height = T.let(tallest_sibling_height, Integer) + 1
      next_list = SubIssueList.find_by(issue_id: parent_sub_issue.source_issue_id)

      # this is a case that we should never encounter (there is a parent issue, but it has no SubIssueList), but logging
      # here would help later debug
      if next_list.nil?
        GitHub.logger.info(
          "SubIssue#update_heights_up_hierarchy_after_destroy encountered an issue without a list",
          "code.namespace": "SubIssue",
          "code.function": "update_heights_up_hierarchy_after_destroy",
          **shared_log_tags
        )
        break
      end

      list_to_update = next_list
    end

    GitHub.dogstats.count("sub_issue.list_updates_made", updated_lists.count, tags: ["after:destroy"])
    updates = updated_lists.each_with_object({}) do |list, hash|
      hash[list.id] = { height: list.height }
    end
    SubIssueList.update(updates.keys, updates.values)
  end

  sig { returns(T::Hash[String, T.untyped]) }
  private def shared_log_tags
    {
      "gh.source_issue.id": self.source_issue_id,
      "gh.source_repo.id": self.source_repository_id,
      "gh.sub_issue.id": self.target_issue_id,
    }
  end

  def reindex_issues
    source&.synchronize_search_index
    target&.synchronize_search_index
  end
end
