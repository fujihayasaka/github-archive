# typed: true
# frozen_string_literal: true

module Profiles
  module User
    class LayoutData < BaseLayoutData
      METHODS_TO_PRELOAD = [
        :achievables_and_tiers,
        :achievements_enabled?,
        :active_sponsorships_as_sponsor,
        :active_sponsorships_as_sponsorable,
        :has_pro_plan_badge?,
        :has_unseen_private_achievement?,
        :has_unseen_public_achievement?,
        :hide_from_viewer?,
        :login_name,
        :open_public_projects_count,
        :organizations,
        :primary_avatar_url,
        :profile_bio,
        :profile_name,
        :repository_count,
        :show_sponsor_button?,
        :site_admin?,
        :site_admin_alerts,
        :spammy?,
        :sponsorable?,
        :sponsored_by_viewer?,
        :typed_object_from_id,
        :user_is_viewer?,
        :viewer_blocking_profile_user?,
        :ignored_user_record,
        :private_contribution_count_enabled?,
      ].freeze

      SKIP_SPONSORS_METHODS = [
        :active_sponsorships_as_sponsor,
        :active_sponsorships_as_sponsorable,
      ].freeze

      SPONSORSHIPS_LIMIT = 13

      def initialize(profile_user:, viewer:, active_tab:, skip_sponsor_preloads: false, previewing: false)
        @profile_user = profile_user
        @viewer = viewer
        @active_tab = active_tab
        @skip_sponsor_preloads = skip_sponsor_preloads
        @metadata = profile_user.user_metadata || UserMetadata.new
        @previewing = previewing
      end

      def self.preload(profile_user:, viewer:, active_tab:, skip_sponsor_preloads: false, previewing: false)
        new(
          profile_user: profile_user,
          viewer: viewer,
          active_tab: active_tab,
          skip_sponsor_preloads: skip_sponsor_preloads,
          previewing: previewing
        ).preload!
      end

      def preload!
        methods_to_preload = if @skip_sponsor_preloads
          METHODS_TO_PRELOAD - SKIP_SPONSORS_METHODS
        else
          METHODS_TO_PRELOAD
        end

        methods_to_preload.map(&method(:send))

        self
      end

      memoize def achievables_and_tiers
        result = measure(metric: "achievables_and_tiers", type: :query) do
          metadata.achievables_and_tiers(visibility: profile_user.profile_settings_visibility)
        end

        # Preload achievable_skin_tone, but only if it's going to be used.
        if result.any? { |achievable, tier| achievable.uses_skin_tone?(tier: tier) }
          achievement_skin_tone
        end

        result
      end

      memoize def achievements_enabled?
        measure(metric: "achievements_enabled", type: :query) do
          profile_user.profile_settings.achievements_enabled?
        end
      end

      memoize def private_contribution_count_enabled?
        measure(metric: "private_contribution_count_enabled", type: :query) do
          profile_user.profile_settings.show_private_contribution_count?
        end
      end

      memoize def achievement_skin_tone
        measure(metric: "preferred_skin_tone", type: :query) do
          profile_user.profile_settings.preferred_emoji_skin_tone
        end
      end

      memoize def global_advisory_credit_count
        measure(metric: "global_advisory_credit_count", type: :count) do
          metadata.global_advisory_credit_count
        end
      end

      memoize def discussion_answered_count
        measure(metric: "discussion_answered_count", type: :count) do
          metadata.discussion_answered_count
        end
      end

      memoize def followers_count
        measure(metric: "followers_count", type: :count) { metadata.followers_count }
      end

      memoize def following_count
        measure(metric: "following_count", type: :count) { metadata.following_count }
      end

      memoize def has_pro_plan_badge?
        measure(metric: "has_pro_plan_badge", type: :query) do
          metadata.has_pro_badge? && profile_user.profile_settings.pro_badge_enabled?
        end
      end

      memoize def bounty_hunter?
        measure(metric: "bounty_hunter", type: :query) { metadata.is_bounty_hunter? }
      end

      memoize def campus_expert?
        measure(metric: "campus_expert", type: :query) { metadata.is_campus_expert? }
      end

      memoize def github_star?
        measure(metric: "github_star", type: :query) { metadata.is_github_star? }
      end

      memoize def packages_count
        if profile_user == viewer
          measure(metric: "packages_public_and_private_count", type: :count) do
            metadata.packages_public_and_private_count
          end
        else
          measure(metric: "packages_count", type: :count) do
            metadata.packages_count
          end
        end
      end

      memoize def sponsorable?
        measure(metric: "sponsorable", type: :query) { profile_user.sponsorable? }
      end

      memoize def sponsored_by_viewer?
        measure(metric: "sponsored_by_viewer", type: :query) do
          profile_user.sponsored_by_viewer?(viewer)
        end
      end

      memoize def stars_count
        measure(metric: "stars_count", type: :count) do
          if GitHub.multi_tenant_enterprise? && viewer&.feature_flag_enabled?(:proxima_emus_omit_profile_star_count, default: false)
            # On Proxima eschew showing the stars count.
            # The star processor that updates the count only considers public
            # and private repos, where Proxima would need to consider private and internal
            # repos.
            0
          else
            metadata.stars_count
          end
        end
      end

      memoize def developer_program_member?
        measure(metric: "developer_program_member", type: :query) do
          metadata.is_developer_program_member?
        end
      end

      memoize def show_developer_program_badge?
        measure(metric: "show_developer_program_badge", type: :query) do
          return false unless GitHub.developer_program_enabled?
          return false if metadata.is_staff? # Employees can not be part of the Developer Program.

          developer_program_member?
        end
      end

      memoize def open_public_projects_count
        measure(metric: "open_public_projects_count", type: :count) { metadata.projects_count }
      end

      memoize def sponsoring_count
        active_sponsoring_count
      end

      def active_and_inactive_sponsoring_count
        if profile_user == viewer
          measure(metric: "public_and_private_active_and_inactive_sponsoring_count", type: :count) do
            metadata.sponsoring_public_and_private_count + metadata.inactive_sponsoring_public_and_private_count
          end
        else
          measure(metric: "active_and_inactive_sponsoring_count", type: :count) do
            metadata.sponsoring_count + metadata.inactive_sponsoring_count
          end
        end
      end

      def active_sponsoring_count
        if profile_user == viewer
          measure(metric: "public_and_private_sponsoring_count", type: :count) do
            metadata.sponsoring_public_and_private_count
          end
        else
          measure(metric: "sponsoring_count", type: :count) do
            metadata.sponsoring_count
          end
        end
      end

      def inactive_sponsoring_count
        if profile_user == viewer
          measure(metric: "public_and_private_inactive_sponsoring_count", type: :count) do
            metadata.inactive_sponsoring_public_and_private_count
          end
        else
          measure(metric: "inactive_sponsoring_count", type: :count) do
            metadata.inactive_sponsoring_count
          end
        end
      end

      memoize def sponsors_count
        measure(metric: "sponsors_count", type: :count) { metadata.sponsors_count }
      end

      memoize def sponsors_public_and_private_count
        measure(metric: "sponsors_public_and_private_count", type: :count) do
          metadata.sponsors_public_and_private_count
        end
      end

      memoize def show_sponsor_button?
        measure(metric: "show_sponsor_button", type: :query) do
          if !GitHub.sponsors_enabled? || user_is_viewer?
            false
          else
            sponsorable?
          end
        end
      end

      def show_follow_button?
        !user_is_viewer?
      end

      memoize def organizations
        measure(metric: "organizations_visible_to_viewer", type: :query) do
          profile_user.organizations_visible_to(viewer).to_a
        end
      end

      memoize def active_sponsorships_as_sponsorable
        measure(metric: "active_sponsorships_as_sponsorable", type: :query) do
          sponsorships = profile_user.
            active_sponsorships_as_sponsorable.
            paid.
            limit(SPONSORSHIPS_LIMIT).
            includes(:sponsor).
            with_linked_org_preloads.
            to_a

          Sponsors::Profile::SponsorAvatarComponent.prefill_necessary_methods(
            sponsorships,
            current_user: @viewer
          )
          sponsorships
        end
      end

      memoize def active_sponsorships_as_sponsor
        measure(metric: "active_sponsorships_as_sponsor", type: :query) do
          sponsorships = profile_user.
            active_sponsorships_as_sponsor_relation.
            paid.
            sponsor_visible_to(@viewer).
            limit(SPONSORSHIPS_LIMIT).
            includes(:sponsorable).
            to_a

          Sponsors::Profile::SponsorAvatarComponent.prefill_necessary_methods(
            sponsorships,
            current_user: @viewer
          )
          sponsorships
        end
      end

      memoize def has_unseen_private_achievement?
        measure(metric: "has_unseen_private_achievement", type: :query) do
          metadata.has_unseen_private_achievement?
        end
      end

      memoize def has_unseen_public_achievement?
        measure(metric: "has_unseen_public_achievement", type: :query) do
          metadata.has_unseen_public_achievement?
        end
      end

      private

      def measure(metric:, type:)
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        result = yield

        GitHub.dogstats.distribution(
          distribution_for_type(type),
          GitHub::Dogstats.duration(start),
          tags: ["#{type}:#{metric}"],
        )

        result
      end

      def distribution_for_type(type)
        if type == :query
          "profiles.layout_data.queries.dist.time"
        else
          "profiles.layout_data.counts.dist.time"
        end
      end
    end
  end
end
