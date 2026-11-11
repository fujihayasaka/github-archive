# typed: true
# frozen_string_literal: true

# Notifications when significant IssueEvents happen
class IssueEventNotification
  include GitHub::UserContent
  include GlobalID::Identification
  attr_reader :issue_event

  delegate :id, :new_record?, :created_at, :permalink,
    :issue, :repository, :async_repository, :entity, :async_entity, :notifications_list, :repository_for_commit,
    to: :issue_event

  # Public: Find an IssueEvent and create a IssueEventNotification wrapping it.
  # This is typically used by Newsies to actually deliver notifications.
  #
  # id - The IssueEvent primary key id.
  #
  # Returns a IssueEventNotification or nil when no IssueEvent exists for the id.
  def self.find_by_id(id)  # rubocop:disable GitHub/FindByDef
    if issue_event = IssueEvent.find_by(id: id)
      new(issue_event)
    end
  end

  def self.find(id)
    find_by_id(id)
  end

  # Public: Create a IssueEventNotification
  #
  # issue_event - The IssueEvent object this notification corresponds to.
  #
  # Returns a IssueEventNotification
  def initialize(issue_event)
    @issue_event = issue_event
  end

  def ==(other)
    self.class == other.class && issue_event == other.issue_event
  end

  # Public: Register the recipient for this notification
  #
  # id - The User ID for the recipient
  #
  # Returns nothing
  def register_recipient(id)
    @recipient = User.find_by(id: id)
  end
  attr_reader :recipient

  # Public: the body for the notification
  def body
    close_text = nil
    body = nil
    closed_reason = should_add_reason ? (issue_event.state_reason || "completed").downcase.gsub("_", " ") : nil
    closed_reason_text = closed_reason ? " as #{closed_reason}" : ""

    case
    when closed_via_commit?
      body = "#{event_type} ##{issue.number}#{closed_reason_text}".dup
      close_text = issue_event.commit_id
      if repository_for_commit.pullable_by?(recipient)
        close_text = "#{repository_for_commit.name_with_display_owner}@#{close_text}" if repository_for_commit != repository
      end
    when closed_via_pr?
      body = "#{event_type} ##{issue.number}#{closed_reason_text}".dup
      pr = issue_event.referencing_issue
      if pr.readable_by?(recipient)
        close_text = "##{pr.number}"
        close_text = "#{pr.repository.name_with_display_owner}#{close_text}" if pr.repository != repository
      end
    when assigned?
      body = "#{event_type} ##{issue.number}".dup
      body << " to @#{issue_event.actor.display_login}"
    when unassigned?
      body = "#{event_type} ##{issue.number}".dup
      body << " from @#{issue_event.actor.display_login}"
    when review_requested?
      if issue_event.subject&.is_a?(Team)
        body = "@#{issue_event.actor.display_login} requested review from @#{issue_event.subject} on: #{issue.repository.name_with_display_owner}##{issue.number} #{issue.title}".dup
      else
        body = "@#{issue_event.actor.display_login} requested your review on: #{issue.repository.name_with_display_owner}##{issue.number} #{issue.title}".dup
      end

      via_codeowner = issue_event.review_request && issue_event.review_request.reasons.any?(&:codeowners?)
      body << " as a code owner" if via_codeowner
    when ready_for_review?
      body = "@#{issue_event.actor.display_login} marked a pull request as ready for review: #{issue.repository.name_with_display_owner}##{issue.number} #{issue.title}".dup
      body << "\n\n"
      body << "View the latest changes: #{issue_event.permalink}"
    when merged_pull_request?
      pr = issue_event.pull_request
      body = "#{event_type} ##{issue.number}".dup
      body << " into #{pr.display_base_ref_name}" if pr.present? && pr.base_ref_exist?
    when converted_to_discussion?
      body = "@#{issue_event.actor.display_login} converted this issue into discussion ##{issue_event.subject.number}".dup
    when removed_from_merge_queue?
      pr = issue_event.pull_request
      body = "##{pr.number} was #{merge_queue_removal_message}".dup
    when added_to_merge_queue?
      pr = issue_event.pull_request
      body = "##{pr.number} was added to the [merge queue](#{merge_queue_link})".dup
    else
      body = "#{event_type} ##{issue.number}#{closed_reason_text}".dup
    end

    body << " via #{close_text}" if close_text
    body << "."
    ERB::Util.force_escape(body)
  end

  # Interal: Whether we should say this was Merged or Closed
  def event_type
    return "Assigned" if assigned?
    return "Merged"   if merged_pull_request?
    issue_event.event.titlecase
  end

  # Internal: Return Boolean telling us if this close was the result of a commit.
  # i.e. a commit that says "fixes NUM_HERE..."
  def closed_via_commit?
    issue_event.close? && issue_event.commit_id.present?
  end

  # Internal: Return Boolean telling us if this close was the result of a PR.
  # i.e. a PR that says "fixes NUM_HERE..."
  def closed_via_pr?
    issue_event.close? && issue_event.referencing_issue_id.present?
  end

  # Internal: Return a Boolean telling us if this was assigned.
  def assigned?
    issue_event.assigned?
  end

  # Internal: Return a Boolean telling us if this was unassigned.
  def unassigned?
    issue_event.unassigned?
  end

  # Internal: Return a Boolean telling us if this was requested.
  def review_requested?
    issue_event.review_requested?
  end

  # Internal: Return a Boolean telling us if this was ready_for_review.
  def ready_for_review?
    issue_event.ready_for_review?
  end

  # Internal: Indicates if the event notification is for an issue that was
  #           converted to a discussion.
  #
  # Returns a Boolean.
  def converted_to_discussion?
    issue_event.event == "converted_to_discussion"
  end

  # Internal: Return a Boolean telling us if this was added_to_merge_queue.
  def added_to_merge_queue?
    issue_event.added_to_merge_queue?
  end

  # Internal: Return a Boolean telling us if this was removed_from_merge_queue.
  def removed_from_merge_queue?
    issue_event.removed_from_merge_queue?
  end

  def merge_queue_removal_message
    case MergeQueues::Entry::RemovalReason.deserialize(issue_event.message&.to_sym)
    when MergeQueues::Entry::RemovalReason::AlreadyMerged
      "automatically removed from the [merge queue](#{merge_queue_link}) due to it being already merged"
    when MergeQueues::Entry::RemovalReason::ChecksTimedOut
      "automatically removed from the [merge queue](#{merge_queue_link}) due to no response for status checks"
    when MergeQueues::Entry::RemovalReason::FailedChecks
      "automatically removed from the [merge queue](#{merge_queue_link}) due to failed status checks"
    when MergeQueues::Entry::RemovalReason::MergeConflict
      "automatically removed from the [merge queue](#{merge_queue_link}) due to a conflict with the base branch"
    when MergeQueues::Entry::RemovalReason::Merged
      "automatically removed from the [merge queue](#{merge_queue_link}) due to the pull request being merged"
    when MergeQueues::Entry::RemovalReason::Manual
      "manually removed from the [merge queue](#{merge_queue_link}) by #{issue_event.actor.display_login}"
    when MergeQueues::Entry::RemovalReason::RollBack
      "removed from the [merge queue](#{merge_queue_link}) due to a roll back"
    when MergeQueues::Entry::RemovalReason::Unknown
      "removed from the [merge queue](#{merge_queue_link}) due to an unknown reason"
    when MergeQueues::Entry::RemovalReason::QueueCleared
      "automatically removed from the [merge queue](#{merge_queue_link}) due to the queue being cleared"
    when MergeQueues::Entry::RemovalReason::BranchProtections
      "automatically removed from the [merge queue](#{merge_queue_link}) due to failing Branch Protection rules"
    else
      "removed from the [merge queue](#{merge_queue_link}) due to an unknown reason"
    end
  end

  def merge_queue_link
    merge_queue = MergeQueue.for(repository: issue.repository, branch: issue.pull_request.base_ref)
    merge_queue ? GitHub.url + merge_queue.async_path_uri.sync.to_s : ""
  end

  # Detect if we're closing a PullRequest due to a merge. We use the merge issue
  # event to detect this since the pull request record may not yet be updated
  # when this event is fired. The merge event is guaranteed to be created before
  # the closed event.
  def merged_pull_request?
    issue.pull_request? && issue.events.merges.any?
  end

  # Internal: the "Thread" is the issue. Used by the notifications rollup logic.
  def notifications_thread
    issue
  end

  # Public: the User is the person who created the IssueEvent. This is used as the
  # sender on outbound email notifications.
  #
  # NOTE: in the case where we don't know the closer, we fallback to issue.user
  # (i.e. the creator).
  #
  # DOUBLE NOTE: Due to the (unfortunate) flipped relation of actor_id in issue
  # events, we have to use issue_event.subject explicitly during assigned issue
  # events.
  def user
    if assigned?
      issue_event.subject || issue.user
    else
      issue_event.actor || issue.user
    end
  end

  # Internal: the author is the user.  Used by notifications delivery logic.
  def notifications_author
    user
  end

  # Public: a unique message id for this notification. Used in outgoing
  # email only. This identifier must be unique for each notification sent.
  def message_id
    prefix = issue.pull_request? ? "pull" : "issue"
    "<#{repository.name_with_display_owner}/#{prefix}/#{issue.number}/issue_event/#{id}@#{GitHub.urls.host_name}>"
  end

  # Internal: user_id - see user
  def user_id
    user && user.id
  end

  def should_add_reason
    return false if issue.pull_request || issue.discussion
    event_type.downcase == "closed"
  end
end
