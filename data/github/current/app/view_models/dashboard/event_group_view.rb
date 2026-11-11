# typed: true
# frozen_string_literal: true

module Dashboard
  class EventGroupView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include ActionView::Helpers::UrlHelper

    TOTAL_EVENTS_SHOWN_INITIALLY = 1
    COMMITS_BY_REF_SHOWN_COUNT = 1

    def initialize(grouped_events:)
      @grouped_events = grouped_events
    end

    def action
      if follow_events?
        "started following"
      elsif push_events?
        "pushed to"
      elsif fork_events?
        "forked"
      elsif watch_events?
        "starred"
      elsif create_events?
        "created"
      elsif public_events?
        "made"
      elsif issue_comment_events? || pull_request_review_comment_events?
        "left"
      elsif release_events?
        "created"
      end
    end

    def repo_ids
      events.map(&:repo_id).compact.uniq
    end

    def trailing_action
      if public_events?
        "public"
      end
    end

    def expandable?(viewer:)
      if push_events?
        expandable_push_events?
      elsif same_target?
        expandable_same_target_events?(viewer: viewer)
      elsif viewer.present? && targets_include_viewer?(viewer: viewer) && events.size == 2
        false
      else
        true
      end
    end

    def expanded?(viewer:)
      if follow_events?
        same_target? && !targets_include_viewer?(viewer: viewer)
      else
        event_type_can_be_grouped_by_target? && same_target?
      end
    end

    def same_target?
      target_identifiers.uniq.size == 1
    end

    def same_actor?
      total_unique_actors == 1
    end

    def list_actors?
      total_unique_actors <= 3
    end

    def unique_actors
      @unique_actors ||= @grouped_events.map(&:sender_record).uniq
    end

    def total_unique_actors
      unique_actors.size
    end

    def sender_record
      unique_actors.first
    end

    def actor_login
      sender_record.display_login
    end

    def actor_id
      first_event.actor_id
    end

    def events
      @grouped_events
    end

    def event_views
      @event_views ||= events.map { |event| Events::View.for(event, grouped: true) }
    end

    def visible_events(viewer:)
      if push_events?
        []
      elsif follow_events?
        visible_follow_events(viewer: viewer)
      else
        events.take(TOTAL_EVENTS_SHOWN_INITIALLY)
      end
    end

    def hidden_events(viewer:)
      if push_events?
        events
      elsif follow_events?
        hidden_follow_events(viewer: viewer)
      else
        events.drop(TOTAL_EVENTS_SHOWN_INITIALLY)
      end
    end

    def first_event
      events.first
    end

    # Public: Returns a view model for the first event in the group.
    #
    # Returns an Events::View instance.
    def first_event_view
      event_views.first
    end

    # Public: Returns a view model for the second event in the group.
    #
    # Returns an Events::View instance.
    def event_for_second_target_user(viewer:)
      if targets_include_viewer?(viewer: viewer)
        event_views.detect { |event| event.target_login != viewer.login } # rubocop:disable GitHub/DoNotAllowLogin
      else
        event_views[1]
      end
    end

    def follow_events?
      first_event.follow_event?
    end

    def issue_comment_events?
      first_event.issue_comment_event?
    end

    def pull_request_review_comment_events?
      first_event.pull_request_review_comment_event?
    end

    def release_events?
      first_event.release_event?
    end

    def issue_comment_parent_type
      if first_event.pull_request_url.present?
        "pull request"
      else
        "issue"
      end
    end

    def public_events?
      events.first.public_event?
    end

    def fork_events?
      first_event.fork_event?
    end

    def icon_name
      first_event_view.icon
    end

    def targets_include_viewer?(viewer:)
      return false unless viewer
      follow_events? && target_names.include?(viewer.login) # rubocop:disable GitHub/DoNotAllowLogin
    end

    def trailing_targets_description(viewer:)
      if follow_events?
        trailing_target_users_description(viewer: viewer)
      elsif push_events?
        repo.try(:nwo)
      elsif watch_events? || fork_events? || public_events? || repository_create_events?
        trailing_target_repos_description
      elsif create_events?
        trailing_target_refs_description
      elsif issue_comment_events? || pull_request_review_comment_events?
        trailing_comments_description
      elsif release_events?
        trailing_releases_description
      end
    end

    def create_events?
      events.first.create_event?
    end

    # Public: Were these CreateEvents that happened within a repository, like creating
    # a branch or tag, as opposed to creating a repository itself?
    #
    # Returns a Boolean.
    def tag_or_branch_create_event?
      create_events? && events.first.ref_type != "repository"
    end

    def push_events?
      first_event.push_event?
    end

    def watch_events?
      first_event.watch_event?
    end

    def visible_commits_grouped_by_ref
      commits_grouped_by_ref.take(COMMITS_BY_REF_SHOWN_COUNT)
    end

    def hidden_commits_grouped_by_ref
      commits_grouped_by_ref.drop(COMMITS_BY_REF_SHOWN_COUNT)
    end

    def click_attributes(org_id: nil, viewer:)
      NewsFeedAnalytics.event_group_click_attributes(event_group(viewer: viewer), org_id: org_id,
                                                     viewer_id: viewer&.id)
    end

    def link_to_trailing_targets_description?
      follow_events? && events.size == 2 && !same_target?
    end

    def show_trailing_targets_description?
      !follow_events? || !same_target? || issue_comment_events? ||
        pull_request_review_comment_events?
    end

    def repository_nwo
      first_event.repo_nwo
    end

    def instrument_view(viewer, org)
      GlobalInstrumenter.instrument("news_feed.event.view",
        event_group: event_group(viewer: viewer),
        target_type: NewsFeedAnalytics::TARGET_TYPE_EVENT_GROUP,
        actor: viewer,
        org: org,
      )
    end

    def most_recent_created_at
      first_event.created_at
    end

    private

    def hidden_follow_events(viewer:)
      if !expandable?(viewer: viewer)
        []
      elsif same_actor?
        events_without_target_user(user: viewer).drop(TOTAL_EVENTS_SHOWN_INITIALLY)
      else
        events.drop(TOTAL_EVENTS_SHOWN_INITIALLY)
      end
    end

    def visible_follow_events(viewer:)
      if same_actor?
        events_without_target_user(user: viewer).take(TOTAL_EVENTS_SHOWN_INITIALLY)
      else
        events.take(TOTAL_EVENTS_SHOWN_INITIALLY)
      end
    end

    def events_with_target_user(user:)
      if user.present?
        events.select { |event| event.target_login == user.login } # rubocop:disable GitHub/DoNotAllowLogin
      else
        events
      end
    end

    def events_without_target_user(user:)
      events - events_with_target_user(user: user)
    end

    def expandable_push_events?
      commits_grouped_by_ref.size > 1
    end

    def expandable_same_target_events?(viewer:)
      if follow_events?
        targets_include_viewer?(viewer: viewer)
      else
        !event_type_can_be_grouped_by_target?
      end
    end

    def event_type_can_be_grouped_by_target?
      follow_events? || watch_events?
    end

    def commits_grouped_by_ref
      @commits_grouped_by_ref ||= events_grouped_by_ref.map do |ref, events|
        Dashboard::CommitGroupView.new(ref: ref, events: events)
      end
    end

    def repository_create_events?
      create_events? && events.first.repository_ref_type?
    end

    # event group payload for analytics
    def event_group(viewer:)
      {
        type: first_event.event_type,
        quantity: events.count,
        includes_viewer: targets_include_viewer?(viewer: viewer),
      }
    end

    def trailing_target_refs_description
      ref_type = events.first.ref_type
      count = target_count
      "#{count} #{ref_type.pluralize(count)}"
    end

    def trailing_comments_description
      unit = "comment".pluralize(target_count)
      "#{target_count} #{unit}"
    end

    def trailing_target_users_description(viewer:)
      if viewer.present? && events.size == 2
        target_names.detect { |name| name != viewer.login } # rubocop:disable GitHub/DoNotAllowLogin
      else
        remaining_count = trailing_target_names.size
        unit = "user".pluralize(remaining_count)
        "#{remaining_count} other #{unit}"
      end
    end

    def trailing_target_repos_description
      unit = "repository".pluralize(target_count)
      "#{target_count} #{unit}"
    end

    def trailing_releases_description
      unit = "release".pluralize(target_count)
      "#{target_count} #{unit}"
    end

    def target_count
      if create_events? || release_events?
        target_identifiers.size
      else
        target_identifiers.uniq.size
      end
    end

    def target_names
      if follow_events?
        @grouped_events.map(&:target_login)
      elsif push_events? || watch_events?
        @grouped_events.map { |_event| repo.name_with_display_owner }
      end
    end

    def target_identifiers
      if follow_events?
        @grouped_events.map(&:target_login)
      elsif push_events? || fork_events? || watch_events? || public_events?
        @grouped_events.map { |event| event.target_id || event.repo_nwo }
      elsif create_events?
        @grouped_events.map do |event|
          target_id = event.payload["ref"] || event.payload["object_name"]
          owner = event.user["display_login"]
          name = event.repo["name"]
          # Disable rubocop linter here because owner is a string and not a user object
          repo_nwo = "#{owner}/#{name}" # rubocop:disable GitHub/DoNotAllowLogin
          "#{repo_nwo}/#{target_id}"
        end
      elsif issue_comment_events? || pull_request_review_comment_events?
        @grouped_events.map(&:comment_id)
      elsif release_events?
        @grouped_events.map(&:repo_nwo)
      end
    end

    def trailing_target_names
      target_names[1..-1]
    end

    def repo
      return @repo if defined?(@repo)
      @repo = first_event.repo_record
    end

    def events_grouped_by_ref
      events.select { |event| event.ref.present? }.group_by(&:ref)
    end
  end
end
