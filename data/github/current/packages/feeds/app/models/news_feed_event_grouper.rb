# typed: true
# frozen_string_literal: true

class NewsFeedEventGrouper
  FOLLOW_MAX_INTERVAL_IN_SECONDS = 7200 # 2 hours
  PUSH_MAX_INTERVAL_IN_SECONDS = 7200 # 2 hours
  WATCH_MAX_INTERVAL_IN_SECONDS = 7200 # 2 hours
  CREATE_MAX_INTERVAL_IN_SECONDS = 7200 # 2 hours
  FORK_MAX_INTERVAL_IN_SECONDS = 7200 # 2 hours
  PUBLIC_MAX_INTERVAL_IN_SECONDS = 7200 # 2 hours
  ISSUE_COMMENT_MAX_INTERVAL_IN_SECONDS = 7200 # 2 hours
  PR_REVIEW_COMMENT_MAX_INTERVAL_IN_SECONDS = 7200 # 2 hours
  RELEASE_MAX_INTERVAL_IN_SECONDS = 86400 # 24 hours

  OVERALL_MAX_INTERVAL_IN_SECONDS = 7200 # 2 hours

  attr_reader :ungrouped_events

  def initialize(ungrouped_events)
    @ungrouped_events = ungrouped_events.dup
  end

  # Public: Process the ungrouped events by pulling out groups of like events, according to the
  # specified grouping policy. Returns a list of event groups that existed in the ungrouped events
  # list.
  #
  # policy - the grouping policy to apply; one of :target or :actor
  #
  # Returns an Array of Arrays of events.
  def apply_grouping_policy(policy)
    event_groups_by_policy(policy)
  end

  private

  def event_groups_by_policy(policy)
    groups = []
    return groups if ungrouped_events.empty?

    still_ungrouped = []

    pregrouped_events = ungrouped_events.group_by do |event|
      policy_pregroup_key(policy, event)
    end
    pregrouped_events.values.each do |pregroup|
      pregroup.sort_by!(&:created_at)
      pregroup.reverse!

      outer_index = 0
      while outer_index < pregroup.size
        base_event = pregroup[outer_index]

        if base_event
          inner_index = outer_index + 1
          group = find_a_group_for(inner_index, base_event, groups, policy, pregroup)
          if group.size > 1
            pregroup[outer_index] = nil
            groups << group
          end
        end

        outer_index += 1
      end

      pregroup.compact!
      still_ungrouped.concat pregroup
    end

    still_ungrouped.sort_by!(&:created_at)
    still_ungrouped.reverse!
    @ungrouped_events = still_ungrouped

    groups
  end

  def find_a_group_for(index, base_event, groups, policy, pregroup)
    group = [base_event]
    start_time = base_event.created_at

    while index < pregroup.size
      other_event = pregroup[index]

      if other_event
        if can_be_grouped?(policy, base_event, other_event)
          pregroup[index] = nil
          group << other_event
        elsif !occurred_within_interval?(start_time, other_event.created_at, OVERALL_MAX_INTERVAL_IN_SECONDS)
          # We're outside the interval of a possible grouping, no more events
          # can match.
          break
        end
      end

      index += 1
    end

    group
  end

  def policy_pregroup_key(policy, event)
    if policy == :target
      target_identifier_for(event)
    else
      event.actor_login
    end
  end

  def can_be_grouped?(policy, base_event, other_event)
    if policy == :target
      can_be_grouped_by_target?(base_event, other_event)
    else
      can_be_grouped_by_actor?(base_event, other_event)
    end
  end

  def can_be_grouped_by_target?(event, other_event)
    return false unless eligible_same_target_events?(event, other_event)

    eligible_watch_events?(event, other_event) || eligible_follow_events?(event, other_event)
  end

  def can_be_grouped_by_actor?(event, other_event)
    return false unless eligible_same_actor_events?(event, other_event)

    eligible_watch_events?(event, other_event) ||
      eligible_follow_events?(event, other_event) ||
      eligible_push_events?(event, other_event) ||
      eligible_fork_events?(event, other_event) ||
      eligible_public_events?(event, other_event) ||
      eligible_create_events?(event, other_event) ||
      eligible_issue_comment_events?(event, other_event) ||
      eligible_pull_request_review_comment_events?(event, other_event) ||
      eligible_release_events?(event, other_event)
  end

  def eligible_same_target_events?(event1, event2)
    !eligible_same_actor_events?(event1, event2) &&
      target_identifier_for(event1) == target_identifier_for(event2)
  end

  def target_identifier_for(event)
    if event.watch_event?
      event.repo_id
    else
      event.target_login
    end
  end

  def eligible_same_actor_events?(event1, event2)
    event1.actor_login == event2.actor_login
  end

  def eligible_create_events?(event1, event2)
    eligible_create_repo_events?(event1, event2) ||
      eligible_create_tag_or_branch_events?(event1, event2)
  end

  def eligible_create_repo_events?(event1, event2)
    eligible_create_events_for_any_ref_type?(event1, event2) &&
      event1.repository_ref_type?
  end

  def eligible_create_tag_or_branch_events?(event1, event2)
    eligible_create_events_for_any_ref_type?(event1, event2) &&
      !event1.repository_ref_type? &&
      event1.actor_login == event2.actor_login &&
      event1.repo_id == event2.repo_id
  end

  def eligible_create_events_for_any_ref_type?(event1, event2)
    max_interval = CREATE_MAX_INTERVAL_IN_SECONDS
    [event1, event2].all?(&:create_event?) &&
      event1.actor_login == event2.actor_login &&
      event1.ref_type == event2.ref_type &&
      occurred_within_interval?(event1.created_at, event2.created_at, max_interval)
  end

  def eligible_issue_comment_events?(event1, event2)
    max_interval = ISSUE_COMMENT_MAX_INTERVAL_IN_SECONDS
    occurred_within_interval?(event1.created_at, event2.created_at, max_interval) &&
      [event1, event2].all?(&:issue_comment_event?) &&
      event1.actor_login == event2.actor_login &&
      event1.issue_id == event2.issue_id
  end

  def eligible_pull_request_review_comment_events?(event1, event2)
    max_interval = PR_REVIEW_COMMENT_MAX_INTERVAL_IN_SECONDS
    occurred_within_interval?(event1.created_at, event2.created_at, max_interval) &&
      [event1, event2].all?(&:pull_request_review_comment_event?) &&
      event1.user_id == event2.user_id &&
      event1.pull_request_id == event2.pull_request_id
  end

  def eligible_follow_events?(event1, event2)
    max_interval = FOLLOW_MAX_INTERVAL_IN_SECONDS
    occurred_within_interval?(event1.created_at, event2.created_at, max_interval) &&
      [event1, event2].all?(&:follow_event?)
  end

  def eligible_fork_events?(event1, event2)
    max_interval = FORK_MAX_INTERVAL_IN_SECONDS
    occurred_within_interval?(event1.created_at, event2.created_at, max_interval) &&
      [event1, event2].all?(&:fork_event?) &&
      event1.actor_login == event2.actor_login
  end

  def eligible_push_events?(event1, event2)
    max_interval = PUSH_MAX_INTERVAL_IN_SECONDS
    occurred_within_interval?(event1.created_at, event2.created_at, max_interval) &&
      [event1, event2].all?(&:push_event?) &&
      event1.repo_id == event2.repo_id &&
      event1.actor_login == event2.actor_login
  end

  def eligible_watch_events?(event1, event2)
    max_interval = WATCH_MAX_INTERVAL_IN_SECONDS
    occurred_within_interval?(event1.created_at, event2.created_at, max_interval) &&
      [event1, event2].all?(&:watch_event?)
  end

  def eligible_public_events?(event1, event2)
    max_interval = PUBLIC_MAX_INTERVAL_IN_SECONDS
    occurred_within_interval?(event1.created_at, event2.created_at, max_interval) &&
      [event1, event2].all?(&:public_event?) &&
      event1.actor_login == event2.actor_login
  end

  def eligible_release_events?(event1, event2)
    max_interval = RELEASE_MAX_INTERVAL_IN_SECONDS
    occurred_within_interval?(event1.created_at, event2.created_at, max_interval) &&
      [event1, event2].all?(&:release_event?) &&
      event1.actor_login == event2.actor_login
  end

  def occurred_within_interval?(first_timestamp, second_timestamp, interval_in_seconds)
    first_timestamp < second_timestamp + interval_in_seconds
  end
end
