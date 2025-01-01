# typed: false
# frozen_string_literal: true

module Dashboard
  class NewsFeedView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    EVENT_GROUPS_PER_PAGE = 30

    attr_reader :timeline, :page
    delegate :visible_events, to: :timeline

    def initialize(current_user:, timeline:, page: nil)
      super(current_user: current_user, timeline: timeline, page: page || 1)
    end

    # Public: Get a list of view models representing individual events or groups of
    # events.
    #
    # :prefill_relations - Boolean indicating if related records used in displaying events should
    #                      be preloaded, to avoid n+1 queries
    #
    # Returns an Array containing `Events::View` and/or `Dashboard::EventGroupView` instances.
    def event_groups(prefill_relations: true)
      set_event_groups
      groups_for_page = @event_groups.paginate(page: page, per_page: EVENT_GROUPS_PER_PAGE)
      prefill_relations_for(groups_for_page) if prefill_relations
      groups_for_page
    end

    # Public: Get a list of user IDs that could possibly be followed by the viewer.
    # If the viewer is the one followed, return the id of the user who followed the viewer.
    #
    # :viewer - User
    #
    # Returns an array of user IDs
    def followable_user_ids(viewer:)
      ids = events_from_grouped_events.map do |event|
        if event.follow_event? && event.target_id != viewer.id
          event.target_id
        else
          event.actor_id
        end
      end

      ids.compact.uniq
    end

    def event_repo_ids
      repo_ids = event_groups.flatten.map do |group|
        if group.is_a?(Events::View)
          group.repo_id
        elsif group.is_a?(Dashboard::EventGroupView)
          group.repo_ids
        end
      end

      repo_ids.flatten.compact.uniq
    end

    # Public: Does the news feed have any pages following the current page?
    #
    # Returns a Boolean.
    def has_next_page?
      next_page_view = self.class.new(
        current_user: current_user,
        timeline: timeline,
        page: page + 1
      )
      groups_for_page = next_page_view.event_groups(prefill_relations: false)
      groups_for_page.any?
    end

    def event_repos
      return @event_repos if defined? @event_repos
      @event_repos = events_from_grouped_events.filter_map(&:repo_record).uniq
    end

    def release_ids
      return @release_ids if defined? @release_ids
      @release_ids = events_from_grouped_events.filter_map(&:release_id)
    end

    def events_from_grouped_events
      return @events_from_grouped_events if defined? @events_from_grouped_events

      @events_from_grouped_events = event_groups.flat_map do |group_or_event|
        if group_or_event.is_a?(Dashboard::EventGroupView)
          group_or_event.event_views
        else
          group_or_event
        end
      end
    end

    private

    # Private: Preload database records for the events in the given groups.
    #
    # event_groups - an Array of Events::View and Dashboard::EventGroupView instances
    #
    # Returns nothing.
    def prefill_relations_for(event_groups)
      events = events_from_groups(event_groups)
      StratocasterEventPrefiller.new(events).preload(:commit_authors)
    end

    # Private: Get the events out of some event groups.
    #
    # event_groups - an Array of Events::View and Dashboard::EventGroupView instances
    #
    # Returns an Array of Stratocaster::Event instances.
    def events_from_groups(event_groups)
      event_groups.flat_map do |view_model|
        if view_model.is_a?(Dashboard::EventGroupView)
          view_model.events
        else
          view_model.model
        end
      end
    end

    def set_event_groups
      @event_groups ||= grouped_and_filtered_events
    end

    def grouped_and_filtered_events
      groups = sorted_event_groups.map do |events_in_group|
        if exclude_events_with_duplicate_target_users?(events_in_group)
          events_in_group.uniq(&:target_login)
        elsif events_in_group.first.watch_event?
          events_in_group.uniq { |event| [event.actor_login, event.repo_nwo] }
        else
          events_in_group
        end
      end

      groups.map { |events_in_group| view_model_for(events_in_group) }
    end

    def view_model_for(events_in_group)
      if events_in_group.size > 1
        Dashboard::EventGroupView.new(grouped_events: events_in_group)
      else
        event = events_in_group.first
        Events::View.for(event, grouped: false)
      end
    end

    def sorted_event_groups
      event_groups = unsorted_groups_of_events.reject(&:empty?)
      event_groups.sort_by { |group| group.first.created_at }.reverse
    end

    def exclude_events_with_duplicate_target_users?(group)
      return false if group.size == 1

      first_event = group.first
      second_event = group.last
      first_event.follow_event? && first_event.actor_login == second_event.actor_login
    end

    def events_excluding_non_unique_follows_by_actor_and_target
      visible_events.uniq do |event|
        if event.follow_event?
          [event.sender_record, event.target_login]
        else
          event
        end
      end
    end

    def unsorted_groups_of_events
      groups = []
      event_grouper = NewsFeedEventGrouper.new(events_excluding_non_unique_follows_by_actor_and_target)
      groups.concat event_grouper.apply_grouping_policy(:target)
      groups.concat event_grouper.apply_grouping_policy(:actor)
      groups + event_grouper.ungrouped_events.map { |event| [event] }
    end
  end
end
