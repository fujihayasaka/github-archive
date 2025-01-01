# typed: true
# frozen_string_literal: true

module Conduit
  module EventAdapter
    class Wiki < Conduit::StratocasterEventAdapter
      include GitHub::Memoizer

      TOTAL_VISIBLE_PAGES = 3

      def html_url
        wiki_path
      end

      def title
        "#{actor_login} #{action_text} a wiki page in #{repo_nwo}"
      end

      def partial_path
        "events/gollum"
      end

      def action_text
        T.bind(self, T.untyped)
        action.to_s.downcase
      end

      memoize def repo_nwo
        repository.name_with_display_owner
      end

      memoize def actor_login
        T.bind(self, T.untyped)
        actor.display_login
      end

      memoize def action
        pages.size == 1 ? pages.first.action : :edited
      end

      memoize def pages
        all_pages.first(TOTAL_VISIBLE_PAGES)
      end

      memoize def remaining_page_count
        all_pages.size - TOTAL_VISIBLE_PAGES
      end

      memoize def more_pages?
        all_pages.size > TOTAL_VISIBLE_PAGES
      end

      def icon
        "book"
      end

      memoize def wiki_path
        repository&.permalink ? "#{repository.permalink}/wiki" : GitHub.url
      end

      private

      memoize def repository
        T.bind(self, T.untyped)
        subject[:repository]
      end

      memoize def all_pages
        T.bind(self, T.untyped)
        page_hashes = (updates || []).map { |u| u.respond_to?(:to_h) ? u.to_h : u }
        page_hashes.map { |hash| Events::GollumView::Page.new(self, hash) }
      end
    end
  end
end
