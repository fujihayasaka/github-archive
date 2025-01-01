# typed: true
# frozen_string_literal: true

module Stafftools
  module RepositoryViews
    class EventsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      include GitHub::Memoizer

      attr_reader :repository
      attr_reader :page_param

      PER_PAGE = 30.freeze

      def page_title
        "#{repository.name_with_owner} - Events"
      end

      memoize def repo_events
        if conduit_enabled?
          feed.items
        else
          Stratocaster::Timeline.new(Stratocasters.domain.repo_event_key(repository)).events(**pagination)
        end
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
        if conduit_enabled?
          feed.next_page.nil?
        else
          repo_events.next_page.nil?
        end
      end

      def prev_page
        if conduit_enabled?
          feed.previous_page
        else
          repo_events.previous_page
        end
      end

      def next_page
        if conduit_enabled?
          feed.next_page
        else
          repo_events.next_page
        end
      end

      def conduit_enabled?
        current_user.feature_enabled?(:conduit_repo_events)
      end

      private

      memoize def twirp_response
        twirp_response = GitHub.conduit_client.get_repository_events(
          viewer: current_user,
          repository_ids: [repository.id]
        )
      end

      memoize def feed
        Conduit::Api::Feed.new(
          repository.owner,
          viewer: current_user,
          twirp_items: twirp_response[:items],
          page: events_page,
          per_page: PER_PAGE
        ).build
      end
    end
  end
end
