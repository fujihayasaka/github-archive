# typed: true
# frozen_string_literal: true

module Profiles
  module User
    class BaseLayoutData
      include GitHub::Memoizer
      include GitHub::FlipperActor
      include GitHub::VexiActor

      METHODS_TO_PRELOAD = [
        :hide_from_viewer?,
        :login_name,
        :primary_avatar_url,
        :profile_bio,
        :profile_name,
        :repository_count,
        :site_admin?,
        :site_admin_alerts,
        :spammy?,
        :typed_object_from_id,
        :user_is_viewer?,
        :viewer_blocking_profile_user?,
        :ignored_user_record,
      ].freeze

      attr_reader :profile_user, :viewer, :active_tab, :metadata, :previewing

      def initialize(profile_user:, viewer:, active_tab:, previewing: false)
        @profile_user = profile_user
        @viewer = viewer
        @previewing = previewing
        @active_tab = active_tab
        @metadata = profile_user.user_metadata || UserMetadata.new
      end

      def self.preload(profile_user:, viewer:, active_tab:, previewing: false)
        new(
          profile_user: profile_user,
          viewer: viewer,
          active_tab: active_tab,
          previewing: previewing,
        ).preload!
      end

      def preload!
        methods_to_preload = METHODS_TO_PRELOAD

        methods_to_preload.map(&method(:send))

        self
      end

      memoize def user_is_viewer?
        profile_user == viewer
      end

      memoize def viewer_blocking_profile_user?
        measure(metric: "viewer_blocking_profile_user", type: :query) do
          viewer&.blocking?(profile_user)
        end
      end

      memoize def hide_from_viewer?
        measure(metric: "hide_from_viewer", type: :query) { profile_user.hide_from_user?(viewer) }
      end

      memoize def site_admin?
        measure(metric: "site_admin", type: :query) { profile_user.site_admin? }
      end

      memoize def spammy?
        measure(metric: "spammy", type: :query) { profile_user.spammy? }
      end

      memoize def repository_count
        if profile_user == viewer
          measure(metric: "public_and_private_repository_count", type: :count) do
            metadata.repository_public_and_private_count
          end
        else
          measure(metric: "public_repository_count", type: :count) do
            metadata.repository_count
          end
        end
      end

      memoize def login_name
        measure(metric: "login_name", type: :query) { profile_user.display_login }
      end

      memoize def profile_bio
        measure(metric: "profile_bio", type: :query) { profile_user.profile_bio }
      end

      memoize def profile_name
        measure(metric: "profile_name", type: :query) { profile_user.profile_name }
      end

      memoize def typed_object_from_id
        measure(metric: "typed_object_from_id", type: :query) { profile_user.global_relay_id }
      end

      memoize def primary_avatar_url
        measure(metric: "primary_avatar_url", type: :query) { profile_user.primary_avatar_url }
      end

      memoize def site_admin_alerts
        measure(metric: "site_admin_alerts", type: :query) do
          layout_data_profile_user = LayoutDataProfileUser.new(
            profile_user: profile_user,
            viewer: viewer,
          )

          if layout_data_profile_user.show_admin_alerts?
            layout_data_profile_user.site_admin_alerts
          end
        end
      end

      memoize def ignored_user_record
        if viewer_blocking_profile_user?
          viewer.ignored_users.find_by(ignored_id: profile_user.id)
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

      class LayoutDataProfileUser
        include UsersHelper

        attr_reader :current_user, :this_user

        def initialize(profile_user:, viewer:)
          @this_user = profile_user
          @current_user = viewer
        end
      end
    end
  end
end
