# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    # are any of sponsor_ids a sponsor for sponsorable
    class IsSponsorCheck < Platform::Loader
      def self.load(sponsorable_id:, sponsor_id:, include_private: false)
        self.for(sponsorable_id, include_private: include_private).load(sponsor_id)
      end

      def initialize(sponsorable_id, include_private:)
        @sponsorable_id = sponsorable_id
        @include_private = include_private
      end

      def fetch(sponsor_ids)
        sponsorships = Sponsorship.active
        sponsorships = sponsorships.privacy_public unless @include_private

        sponsorships = sponsorships
          .with_user_or_org_sponsorable(@sponsorable_id)
          .from_sponsor(sponsor_ids)
          .distinct

        sponsorships.pluck(:sponsor_id).each_with_object(Hash.new(false)) do |sponsor_id, result|
          result[sponsor_id] = true
        end
      end
    end
  end
end
