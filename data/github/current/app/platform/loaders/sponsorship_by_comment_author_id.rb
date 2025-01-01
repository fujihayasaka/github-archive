# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class SponsorshipByCommentAuthorId < Platform::Loader
      def self.load(viewer, sponsorable, comment_author_id)
        self.for(viewer, sponsorable).load(comment_author_id)
      end

      def initialize(viewer, sponsorable)
        @viewer = viewer
        @sponsorable = sponsorable
      end

      # Public: Look up the Sponsorship (if any) of highest priority between
      # each given comment_author_id and the sponsorable. Sponsorship can be
      # direct or indirect via an Organization where the comment_author_id
      # belongs to an admin of the sponsoring org.
      #
      # comment_author_ids - Array of Integer IDs of User
      #
      # Returns a Hash[comment_author_id] => Sponsorship
      def fetch(comment_author_ids)
        return Hash.new unless @sponsorable&.sponsorable?

        GitHub.dogstats.distribution_time("sponsors.sponsorship_by_comment_author_loader.time", tags: tags) do
          if sponsors_indirect_sponsorships_loader_enabled?
            highest_priority_sponsorship_by_sponsor_id(sponsorships_by_sponsor_id(comment_author_ids))
          else
            sponsorship_by_sponsor_id(comment_author_ids)
          end
        end
      end

      private

      def hash_of_empty_sets_keyed_by(keys)
        keys.uniq.each_with_object({}) do |key, hash|
          hash[key] ||= Set.new
        end
      end

      def adminable_org_ids_by_user_id_for(user_ids)
        user_id_org_id_pairs = ::Ability.user_admin_on_organizations(actor_id: user_ids)
          .pluck(:actor_id, :subject_id)
        adminable_org_ids_by_user_id = hash_of_empty_sets_keyed_by(user_ids)

        user_id_org_id_pairs.each do |user_id, org_id|
          adminable_org_ids_by_user_id[user_id] << org_id
        end
        adminable_org_ids_by_user_id
      end

      # Private: Get Sponsorships between sponsors and the sponsorable. Note
      # that when indexing by the sponsor_id column of the Sponsorship
      # table, if the sponsor is an org the sponsor_id is the org_id
      #
      # sponsor_ids - Array of Integer IDs of User
      #
      # Returns a Hash[sponsor_id] => Sponsorship
      def sponsorship_by_sponsor_id(sponsor_ids)
        Sponsorship.join_sponsors_listings_on_sponsorable
          .merge(SponsorsListing.with_approved_state)
          .active
          .from_sponsor(sponsor_ids)
          .sponsor_visible_to(@viewer)
          .with_user_or_org_sponsorable(@sponsorable)
          .includes(:sponsorable, :sponsor)
          .index_by(&:sponsor_id)
      end

      # Private: Get direct and indirect Sponsorships between sponsors and the sponsorable
      #
      # sponsor_ids - Array of Integer IDs of User
      #
      # Returns a Hash[sponsor_id] => [Sponsorship]
      def sponsorships_by_sponsor_id(sponsor_ids)
        adminable_org_ids_by_user_id = adminable_org_ids_by_user_id_for(sponsor_ids)
        org_ids = adminable_org_ids_by_user_id.values.map(&:to_a).flatten
        user_and_org_ids = sponsor_ids + org_ids

        sponsorship_by_user_or_org_id = sponsorship_by_sponsor_id(user_and_org_ids)

        sponsorships = sponsorship_by_user_or_org_id.values
        GitHub::PrefillAssociations.prefill_batch_method(sponsorships, :sponsors_invoiced?)

        sponsorships_by_user_id = hash_of_empty_sets_keyed_by(sponsor_ids)
        sponsorship_by_user_or_org_id.each do |sponsorship_sponsor_id, sponsorship|
          # If sponsorship_sponsor_id is a User
          if sponsorships_by_user_id.key?(sponsorship_sponsor_id)
            sponsorships_by_user_id[sponsorship_sponsor_id] << sponsorship
          else
            # Map sponsorship to org admin (sponsor_id)
            adminable_org_ids_by_user_id.each do |org_admin_id, adminable_org_ids|
              if adminable_org_ids.include?(sponsorship_sponsor_id)
                sponsorships_by_user_id[org_admin_id] << sponsorship
              end
            end
          end
        end

        sponsorships_by_user_id
      end

      # Private: Create a Hash of highest priority Sponsorship for each user, where the
      # user is either directly the sponsor or is an admin of the org sponsor.
      #
      # sponsorships_by_sponsor_id - Hash[sponsor_id] => [Sponsorship]
      #
      # Returns a Hash[Integer User ID] => Sponsorship
      def highest_priority_sponsorship_by_sponsor_id(sponsorships_by_sponsor_id)
        sponsorships_by_sponsor_id.each_with_object({}) do |(sponsor_id, sponsorships), hash|
          hash[sponsor_id] = Sponsorship.highest_priority_sponsorship(
            sponsorships,
            include_premium_sponsorships: sponsors_indirect_sponsorships_loader_enabled?
          )
        end
      end

      def tags
        ["sponsors_indirect_sponsorships_loader_enabled:#{sponsors_indirect_sponsorships_loader_enabled?}"]
      end

      def sponsors_indirect_sponsorships_loader_enabled?
        return @sponsors_indirect_sponsorships_loader_enabled if defined?(@sponsors_indirect_sponsorships_loader_enabled)

        @sponsors_indirect_sponsorships_loader_enabled = GitHub.flipper[:sponsors_indirect_sponsorships_loader].enabled?(@viewer)
      end
    end
  end
end
