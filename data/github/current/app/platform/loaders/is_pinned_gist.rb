# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class IsPinnedGist < Platform::Loader
      def self.load(profile_owner_id:, gist_id:)
        self.for(profile_owner_id).load(gist_id)
      end

      def initialize(profile_owner_id)
        @profile_owner_id = profile_owner_id
      end

      def fetch(gist_ids)
        pinned_gist_ids = Profile.
          where(user_id: @profile_owner_id).
          joins(:profile_pins).
          where(profile_pins: { pinned_item_id: gist_ids }).
          merge(ProfilePin.gists).
          pluck(:pinned_item_id)

        pinned_gist_ids.each_with_object(Hash.new(false)) do |gist_id, result|
          result[gist_id] = true
        end
      end
    end
  end
end
