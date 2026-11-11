# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class IsFollowingCheck < Platform::Loader
      def self.load(viewer_id, user_id)
        self.for(viewer_id).load(user_id)
      end

      def self.load_all(viewer_id, user_ids)
        loader = self.for(viewer_id)

        Promise.all(user_ids.map { |user_id| loader.load(user_id) })
      end

      def initialize(viewer_id)
        @viewer_id = viewer_id
      end

      def fetch(user_ids)
        User.bulk_following_check(@viewer_id, user_ids)
      end
    end
  end
end
