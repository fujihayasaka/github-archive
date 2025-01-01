# typed: strict
# frozen_string_literal: true

module Profiles
  module Organization
    class SponsorsComponent < ApplicationComponent
      extend T::Sig
      include AvatarHelper

      MAX_SPONSORS_TO_DISPLAY = 14

      sig { params(profile_layout_data: T.nilable(Profiles::Organization::LayoutData)).void }
      def initialize(profile_layout_data:)
        @profile_layout_data = profile_layout_data
      end

      private

      sig { returns T::Boolean }
      def render?
        return false unless @profile_layout_data && GitHub.sponsors_enabled?
        non_hidden_sponsorships.present? && profile_layout_data.profile_organization.present?
      end

      sig { returns(Profiles::Organization::LayoutData) }
      def profile_layout_data
        # Called after verifying we have a non-nil value in #render?:
        T.must(@profile_layout_data)
      end

      sig { returns T::Array[Sponsorship] }
      memoize def non_hidden_sponsorships
        all_sponsorships.reject do |sponsorship|
          spammy_user_ids_to_exclude.include?(sponsorship.sponsorable_id) ||
            spammy_user_ids_to_exclude.include?(sponsorship.sponsor_id)
        end
      end

      sig { returns T::Array[Sponsorship] }
      memoize def all_sponsorships
        # Visibility doesn't matter for received sponsorships, will show a generic representation for sponsors
        # the viewer can't know the identity of, so don't need to filter based on sponsorship privacy or who
        # the viewer is:
        receiving_scope = org.active_sponsorships_as_sponsorable.listing_approved

        linked_org_sponsor_ids_by_org_id = { org.id => sponsoring_linked_organization_id }

        # For sponsorships this org is funding, only include those where viewer can know this org is the sponsor:
        funding_scope = T.unsafe(org.active_sponsorships_as_sponsor_relation).sponsor_visible_to(current_user,
          linked_org_sponsor_ids_by_org_id: linked_org_sponsor_ids_by_org_id)

        sponsorships = receiving_scope.or(funding_scope).order(id: :desc).to_a
      end

      sig { returns ::Organization }
      memoize def org
        profile_layout_data.profile_organization
      end

      sig { returns T::Set[Integer] }
      memoize def spammy_user_ids_to_exclude
        if GitHub.spamminess_check_enabled?
          if logged_in? && current_user.site_admin?
            Set.new # staff can view spammers so don't exclude any
          else
            sponsorship_users.select(&:spammy?).map(&:id).to_set
          end
        else
          Set.new
        end
      end

      sig { returns T.nilable(Integer) }
      memoize def sponsoring_linked_organization_id
        org.sponsoring_linked_organization_id
      end

      # Private: All relevant users for sponsorship
      sig { returns T::Array[::User] }
      memoize def sponsorship_users
        ::User.where(id: sponsorship_user_ids).to_a
      end

      # Private: All relevant user IDs for sponsorships to check for spamminess and rank by relevance to the viewer.
      sig { returns T::Array[Integer] }
      memoize def sponsorship_user_ids
        all_sponsorships
          .map { |sponsorship| org_is_sponsor?(sponsorship) ? sponsorship.sponsorable_id : sponsorship.sponsor_id }
          .uniq
      end

      # Private: Sponsorships where this organization is on the receiving end, it's the one being sponsored.
      sig { returns T::Array[Sponsorship] }
      memoize def sponsorships_as_maintainer
        non_hidden_sponsorships
          .select { |sponsorship| sponsorship.sponsorable_id == org.id }
      end

      # Private: Sponsorships coming from this organization, it's the one sponsoring someone else. Includes
      # those it's paying for itself as well as those where it gets credit for the sponsorship but another org pays.
      sig { returns T::Array[Sponsorship] }
      memoize def sponsorships_as_sponsor
        non_hidden_sponsorships.select { |sponsorship| org_is_sponsor?(sponsorship) }
      end

      # Private: Does the org whose profile we're showing represent the sponsor in the given sponsorship?
      sig { params(sponsorship: Sponsorship).returns T::Boolean }
      def org_is_sponsor?(sponsorship)
        return true if sponsorship.sponsor_id == org.id
        return false unless sponsoring_linked_organization_id
        sponsorship.sponsor_id == sponsoring_linked_organization_id
      end

      # Private: All relevant user IDs for sponsorships, sorted such that the users most interesting and relevant
      # to the viewer are first.
      sig { returns T::Array[Integer] }
      memoize def ranked_sponsorship_user_ids
        if logged_in?
          T.unsafe(::User).ranked_for_ids(current_user, scoped_ids: sponsorship_user_ids)
        else
          []
        end
      end

      sig { returns T::Array[Sponsorship] }
      memoize def limited_sponsorships_as_maintainer
        results = if sponsorships_as_maintainer_overflow_count > 0
          sponsorships_as_maintainer.take(MAX_SPONSORS_TO_DISPLAY - 1)
        else
          sponsorships_as_maintainer
        end

        GitHub::PrefillAssociations.prefill_associations(results,
          [:sponsor, sponsor: { sponsoring_parent_organization_profile: :organization }],
          available_records: sponsorship_users,
        )
        Sponsors::Profile::SponsorAvatarComponent.prefill_necessary_methods(results, current_user: current_user)
        results
      end

      sig { returns T::Array[Sponsorship] }
      def sorted_sponsorships_as_maintainer
        sorted_public_sponsorships + private_sponsor_sponsorships
      end

      sig { returns T::Array[Sponsorship] }
      def sorted_public_sponsorships
        public_sponsorships = limited_sponsorships_as_maintainer.select(&:privacy_public?)
        now = Time.now
        sorted_public_sponsorships = public_sponsorships.sort_by do |sponsorship|
          relevance_to_viewer = ranked_sponsorship_user_ids.index(sponsorship.sponsor_id)
          time_ago = now
          sponsorship_start_time = sponsorship.activated_at || sponsorship.created_at
          time_ago -= sponsorship_start_time if sponsorship_start_time
          [relevance_to_viewer, time_ago]
        end
        sorted_public_sponsorships
      end

      sig { returns T::Array[Sponsorship] }
      def private_sponsor_sponsorships
        limited_sponsorships_as_maintainer.reject(&:privacy_public?)
      end

      sig { returns T::Array[Sponsorship] }
      def sorted_sponsorships_as_sponsor
        unsorted_sponsorships = if sponsorships_as_sponsor_overflow_count > 0
          sponsorships_as_sponsor.take(MAX_SPONSORS_TO_DISPLAY - 1)
        else
          sponsorships_as_sponsor
        end
        GitHub::PrefillAssociations.prefill_associations(unsorted_sponsorships, :sponsorable,
          available_records: sponsorship_users)
        now = Time.now
        unsorted_sponsorships.sort_by do |sponsorship|
          relevance_to_viewer = ranked_sponsorship_user_ids.index(sponsorship.sponsorable_id)
          time_ago = now
          sponsorship_start_time = sponsorship.activated_at || sponsorship.created_at
          time_ago -= sponsorship_start_time if sponsorship_start_time
          [relevance_to_viewer, time_ago]
        end
      end

      sig { returns Integer }
      memoize def sponsorships_as_maintainer_overflow_count
        [sponsorships_as_maintainer.size - MAX_SPONSORS_TO_DISPLAY, 0].max
      end

      sig { returns Integer }
      memoize def sponsorships_as_sponsor_overflow_count
        [sponsorships_as_sponsor.size - MAX_SPONSORS_TO_DISPLAY, 0].max
      end
    end
  end
end
