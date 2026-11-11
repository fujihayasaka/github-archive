# typed: strict
# frozen_string_literal: true

module Sponsors
  module Orgs
    class SponsoringComponent < ApplicationComponent
      include AvatarHelper

      INACTIVE_FILTER_PARAM = "inactive"

      class SponsorshipFilter < T::Enum
        enums do
          Active = new
          Inactive = new
        end
      end

      # sponsor - Organization who is doing the sponsoring
      # sponsorships - ActiveRecord::Relation of Sponsorship records
      # is_viewer_member_of_sponsor - Boolean indicating whether the currently authenticated User is a member of
      #                               `sponsor`; possible to be true when `sponsor` is an Organization
      # page - which page of sponsorships to show, defaults to the first
      # per_page - how many sponsorships to show at a time
      # total_dependencies - how many dependencies this organization has
      # viewer_can_manage_sponsorships - Boolean indicating whether the viewer has permission to manage the
      #                                  sponsorships for the given sponsor
      sig do
        params(
          sponsor: GitHubSponsors::Types::Sponsor,
          sponsorships: T.any(T::Array[Sponsorship], ActiveRecord::Relation),
          is_viewer_member_of_sponsor: T::Boolean,
          page: Integer,
          per_page: Integer,
          total_dependencies: Integer,
          viewer_can_manage_sponsorships: T::Boolean,
          filter: SponsorshipFilter,
        ).void
      end
      def initialize(
        sponsor:,
        sponsorships:,
        is_viewer_member_of_sponsor:,
        page: 1,
        per_page: 20,
        total_dependencies: 0,
        viewer_can_manage_sponsorships: false,
        filter: SponsorshipFilter::Active
      )
        @sponsor = sponsor
        @all_sponsorships = sponsorships
        @is_viewer_member_of_sponsor = is_viewer_member_of_sponsor
        @total_dependencies = total_dependencies
        @page = page
        @per_page = per_page
        @viewer_can_manage_sponsorships = viewer_can_manage_sponsorships
        @filter = filter
      end

      private

      sig { returns(T::Boolean) }
      def render?
        @sponsor.organization? && GitHub.sponsors_enabled?
      end

      sig { returns(T::Boolean) }
      def viewer_is_sponsor_member?
        @is_viewer_member_of_sponsor
      end

      sig { returns(T::Boolean) }
      def viewer_can_manage_sponsorships?
        @viewer_can_manage_sponsorships
      end

      sig { returns(T.any(T::Array[Sponsorship], ActiveRecord::Relation)) }
      memoize def sponsorships
        # Preload profile for display name, preload Sponsors listing for featured_description
        # when showing `sponsorable.sponsors_bio`:
        preloads = [:sponsors_listing, { sponsorable: [:profile] }]
        preloads << :tier if viewer_can_manage_sponsorships?

        sponsorships_to_show = T.unsafe(visible_sponsorships).ranked_for_public_profile
        sponsorships_to_show = case @filter
        when SponsorshipFilter::Active
          sponsorships_to_show.active
        when SponsorshipFilter::Inactive
          sponsorships_to_show.inactive
        else
          T.absurd(@filter)
        end

        result = sponsorships_to_show.includes(preloads).paginate(page: @page, per_page: @per_page)
        GitHub::PrefillAssociations.prefill_associations(result.map(&:sponsorable), :sponsors_listing,
          available_records: result.map(&:sponsors_listing))
        GitHub::PrefillAssociations.prefill_batch_method(result, :pending_subscription_item_change)
        Sponsorship.reject_blocked_sponsorships(result, current_user: current_user)
      end

      sig { returns(T.any(T::Array[Sponsorship], ActiveRecord::Relation)) }
      memoize def visible_sponsorships
        if viewer_is_sponsor_member? || viewer_can_manage_sponsorships?
          @all_sponsorships
        else
          T.unsafe(@all_sponsorships).privacy_public
        end
      end

      sig { returns(T::Set[Integer]) }
      memoize def sponsorable_ids
        Set.new(sponsorships.map(&:sponsorable_id))
      end

      sig { returns(T::Hash[Integer, T::Boolean]) }
      memoize def viewer_sponsoring_status_by_sponsorable_id
        result = Hash.new

        if logged_in?
          sponsoring_checker = Platform::Loaders::IsSponsoringCheck.new(current_user.id, viewer: current_user)
          result.merge!(sponsoring_checker.fetch(sponsorable_ids))
        end

        result
      end

      sig { params(sponsorable_id: Integer).returns(T::Boolean) }
      def viewer_is_sponsoring?(sponsorable_id)
        # We have to fallback to `false` here, instead of relying on the Hash's default value,
        # because Sorbet doesn't support setting a non-nil default
        viewer_sponsoring_status_by_sponsorable_id[sponsorable_id] || false
      end

      sig { returns(T::Boolean) }
      def viewer_can_admin_sponsors_listing?
        current_user&.can_admin_sponsors_listings?
      end

      sig { returns(T::Array[Integer]) }
      def already_sponsored_sponsorable_ids
        viewer_sponsoring_status_by_sponsorable_id.select { |_sponsorable_id, is_sponsoring| is_sponsoring }.keys
      end

      # Private: Get a list of user and organization IDs that are sponsorable that the viewer isn't already
      # sponsoring. You can't sponsor someone you're already sponsoring.
      sig { returns(T::Set[Integer]) }
      def not_yet_sponsored_sponsorable_ids
        sponsorable_ids - already_sponsored_sponsorable_ids
      end

      sig { returns(T::Set[Integer]) }
      def spammy_or_blocking_viewer_sponsorable_ids
        ids = User.spammy_or_blocking(current_user).where(id: not_yet_sponsored_sponsorable_ids).pluck(:id)
        Set.new(ids)
      end

      sig { returns(T::Set[Integer]) }
      def ids_of_sponsorables_viewer_can_sponsor
        ids = sponsorable_ids - spammy_or_blocking_viewer_sponsorable_ids
        ids -= [current_user.id] if logged_in?
        ids
      end

      sig { returns(T::Hash[Integer, T::Boolean]) }
      memoize def sponsorability_status_for_viewer_by_sponsorable_id
        ids_of_sponsorables_viewer_can_sponsor
          .each_with_object(Hash.new) do |user_id, hash|
            hash[user_id] = true
          end
      end

      sig { params(sponsorable_id: Integer).returns(T::Boolean) }
      def viewer_can_sponsor?(sponsorable_id)
        return false if viewer_is_sponsoring?(sponsorable_id)
        # We have to fallback to `false` here, instead of relying on the Hash's default value,
        # because Sorbet doesn't support setting a non-nil default
        sponsorability_status_for_viewer_by_sponsorable_id[sponsorable_id] || false
      end

      sig { returns(Integer) }
      memoize def active_sponsoring_count
        T.unsafe(visible_sponsorships).active.count
      end

      sig { returns(Integer) }
      memoize def inactive_sponsoring_count
        T.unsafe(visible_sponsorships).inactive.count
      end

      sig { returns(T::Boolean) }
      def show_sponsorships?
        sponsorships.any?
      end

      sig { returns(String) }
      def blank_slate_message
        if !has_visible_sponsorships?
          "#{@sponsor.display_login} hasn’t sponsored any users yet."
        elsif filtering_active?
          "#{@sponsor.display_login} doesn’t have any active sponsorships."
        else
          "#{@sponsor.display_login} doesn’t have any past sponsorships."
        end
      end

      sig { returns(T::Boolean) }
      def filtering_active?
        @filter == SponsorshipFilter::Active
      end

      sig { returns(T::Boolean) }
      def filtering_inactive?
        @filter == SponsorshipFilter::Inactive
      end

      sig { returns(T::Boolean) }
      memoize def has_visible_sponsorships?
        visible_sponsorships.any?
      end
    end
  end
end
