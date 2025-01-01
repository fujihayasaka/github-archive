# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class CanFollowCheck < Platform::Loader
      def self.load(viewer, user_id)
        self.for(viewer).load(user_id)
      end

      def self.load_all(viewer, user_ids)
        loader = self.for(viewer)

        Promise.all(user_ids.map { |user_id| loader.load(user_id) })
      end

      def initialize(viewer)
        @viewer = viewer
      end

      def fetch(user_ids)
        User.bulk_can_follow_check(@viewer.id, user_ids)
      end
    end
  end
end
