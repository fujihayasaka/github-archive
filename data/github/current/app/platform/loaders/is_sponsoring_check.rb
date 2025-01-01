# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    # does this sponsor sponsor any of the sponsorable_ids
    class IsSponsoringCheck < Platform::Loader
      def self.load(sponsor_id:, sponsorable_id:, viewer: nil, tier_ids: nil)
        self.for(sponsor_id, viewer: viewer, tier_ids: tier_ids).load(sponsorable_id)
      end

      def initialize(sponsor_id, viewer:, tier_ids: nil)
        @sponsor_id = sponsor_id
        @viewer = viewer
        @tier_ids = tier_ids
      end

      def fetch(sponsorable_ids)
        sponsorable_ids = Set.new(sponsorable_ids) unless sponsorable_ids.is_a?(Set)
        sponsorable_ids = sponsorable_ids.delete_if(&:nil?)
        sponsorships = Sponsorship.active
        sponsorships = sponsorships.with_tier(@tier_ids) if @tier_ids

        # Make sure to include only sponsorships whose sponsor is visible to the viewer if we're
        # looking up sponsorships from someone other than the authenticated user:
        if @viewer.nil? || @viewer.id != @sponsor_id
          sponsorships = sponsorships.sponsor_visible_to(@viewer)
        end

        sponsorships = sponsorships.from_sponsor(@sponsor_id)
        if sponsorable_ids.any?
          sponsorships = sponsorships.with_user_or_org_sponsorable(sponsorable_ids)
        end

        if sponsorable_ids.empty?
          Hash.new(sponsorships.any?)
        else
          results = Hash.new(false)

          sponsorships.pluck(:sponsorable_id).each_with_object(results) do |sponsorable_id, result|
            result[sponsorable_id] = true
          end
        end
      end
    end
  end
end
