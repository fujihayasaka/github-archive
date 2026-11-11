# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class LfsNetworksByUsage < Platform::Loader
      def self.load(owner_id)
        self.for.load(owner_id)
      end

      def fetch(owner_ids)
        owner_ids.map do |owner_id|
          unless from = ::User.find_by(id: owner_id)&.first_day_in_lfs_cycle&.to_time&.utc
            # No LFS billing?  No problem.
            next
          end
          [owner_id, ::Asset::Activity.fetch_for_owner_by_network(:lfs, owner_id, from, Time.now.utc)]
        end.compact.to_h
      end
    end
  end
end
