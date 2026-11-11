# typed: true
#frozen_string_literal: true

module Platform
  module Loaders
    class UserBlockedCheck < Platform::Loader
      include Scientist

      def self.load(user_id, ignored_id)
        self.for.load([user_id, ignored_id])
      end

      def fetch(user_id_and_ignored_ids)
        user_ids = user_id_and_ignored_ids.group_by(&:first).keys

        # in most of the cases, a user has no blocked users
        # in some cases, a user is blocking a small number of users
        # for performance reason, to avoid a performance hit when we have a large number of ignore_ids
        # we don't filter with ignored_ids at the database level so that we can quickly
        # find all ignored_users for a given user
        # we then filter in-memory - this can save multiple seconds when the number of ignored_ids is large
        scope = IgnoredUser.where(user_id: user_ids)
        selected_attributes = [:user_id, :ignored_id]
        results = scope.pluck(*selected_attributes)

        results.each_with_object(Hash.new { false }) do |(user_id, ignored_id), user_and_ignored_ids|
          key = [user_id, ignored_id]
          user_and_ignored_ids[key] = true if user_id_and_ignored_ids.include?(key)
        end
      end
    end
  end
end
