# typed: strict
# frozen_string_literal: true

module Profiles
  module User
    class SponsorsComponent < ApplicationComponent
      extend T::Sig
      include UsersHelper
      include AvatarHelper

      sig { params(profile_layout_data: Profiles::User::LayoutData).void }
      def initialize(profile_layout_data:)
        @profile_layout_data = profile_layout_data
      end

      private

      sig { returns(Profiles::User::LayoutData) }
      attr_reader :profile_layout_data

      sig { returns(T::Boolean) }
      def render?
        return false unless GitHub.sponsors_enabled?
        profile_layout_data.sponsors_count > 0 || profile_layout_data.sponsoring_count > 0
      end

      sig { returns(T::Array[Sponsorship]) }
      memoize def sponsorships_as_sponsorable
        profile_layout_data.active_sponsorships_as_sponsorable
      end

      sig { returns(T::Array[Sponsorship]) }
      memoize def sponsorships_as_sponsor
        profile_layout_data.active_sponsorships_as_sponsor
      end

      sig { returns(Integer) }
      memoize def sponsors_overflow_count
        profile_layout_data.sponsors_public_and_private_count - Profiles::User::LayoutData::SPONSORSHIPS_LIMIT
      end

      sig { returns(Integer) }
      memoize def sponsoring_overflow_count
        # We might not have fetched all sponsorships that are visible to the viewer (viewer might have access to some
        # private sponsorships but not all), but we don't want to fetch the actual amount visible to the viewer to
        # save making another query, so use the public sponsorship count as an approximate value:
        total = [sponsorships_as_sponsor.size, profile_layout_data.sponsoring_count].max
        total - Profiles::User::LayoutData::SPONSORSHIPS_LIMIT
      end
    end
  end
end
