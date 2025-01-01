# typed: true
# frozen_string_literal: true

module Stafftools
  module RepositoryViews
    class EventsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      include Stratocaster::Domain::Provider

      attr_reader :repository
      attr_reader :page_param

      def page_title
        "#{repository.name_with_owner} - Events"
      end

      def repo_events
        @repo_events ||=
          Stratocaster::Timeline.new(stratocaster_domain.repo_event_key(repository)).events(**pagination)
      end

      def events_page
        @events_page ||= [page_param.to_i, 1].max
      end

      def pagination
        { page: events_page, per_page: 30 }
      end

      def multiple_pages?
        events_page > 1 || !on_last_page?
      end

      def on_last_page?
        repo_events.next_page.nil?
      end

      def prev_page
        repo_events.previous_page
      end

      def next_page
        repo_events.next_page
      end

    end
  end
end
