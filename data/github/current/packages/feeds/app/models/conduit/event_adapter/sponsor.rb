# typed: true
# frozen_string_literal: true

module Conduit
  module EventAdapter
    class Sponsor < Conduit::StratocasterEventAdapter

      def html_url
        T.bind(self, T.untyped)
        sponsor_path
      end

      def title
        T.bind(self, T.untyped)
        description
      end

      def partial_path
        "events/sponsor"
      end

      def show_event_details?(viewer:)
        T.bind(self, T.untyped)
        viewer_is_sponsorable?(viewer) || target_info_present?
      end

      def viewer_is_sponsorable?(viewer)
        T.bind(self, T.untyped)
        return false unless viewer.respond_to?(:id) && sponsorable.respond_to?(:id)

        !!(viewer && viewer.id == sponsorable.id)
      end

      def target_login
        T.bind(self, T.untyped)
        source
      end

      def icon
        "feed-heart"
      end

      def target_info_present?
        T.bind(self, T.untyped)
        return false unless sponsorable.respond_to?(:followers) && sponsorable.respond_to?(:public_repos) && sponsorable.respond_to?(:bio)

        return true if sponsorable.followers && sponsorable.followers > 0
        return true if sponsorable.public_repos && sponsorable.public_repos > 0
        sponsorable.bio.present?
      end

      private

      def sponsor_path
        sponsor.permalink
      end

      def sponsor
        T.bind(self, T.untyped)
        actor
      end

      def sponsorable
        T.bind(self, T.untyped)
        subject
      end
    end
  end
end
