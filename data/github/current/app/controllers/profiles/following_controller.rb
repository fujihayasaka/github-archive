# typed: true
# frozen_string_literal: true

module Profiles
  class FollowingController < ApplicationController
    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Repositories,
      ApplicationRecord::Configurations,
      ApplicationRecord::Billing,
      only: [:index]

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:index],
      optional: true

    PAGE_SIZE = 50

    include ProfilesHelper
    include UserContributionsHelper

    set_statsd_sample_rate 0.01, only: :index

    around_action :record_profile_stats, only: :index
    before_action :require_user, only: :index
    before_action :ensure_profile_visible
    skip_before_action :cap_pagination, only: :index

    javascript_bundle :profile
    stylesheet_bundle :profile

    def index
      # We're shortcircuiting this for mannequins as it is causing 500s down the line
      return render_404 if this_user.mannequin?

      respond_to do |format|
        format.html do
          instrument_hydro

          render_user_profile
        end
      end
    end

    private

    def render_user_profile
      # Count without the join to users if possible
      total_entries = this_user.following_count_for_viewer(current_user)

      followings = T.let([], T.untyped)

      science("user_profile_following_fast_pagination") do |e|
        e.use do
          followings = this_user.
            following_for_viewer(current_user).
            reorder("followers.created_at DESC").
            paginate(page: current_page, per_page: PAGE_SIZE, total_entries: total_entries).
            includes(:profile)

          followings.to_a # this just needs to force the query run inside the block, this can be removed later
        end

        e.try do
          following_user_ids = Following.
            where(user_id: this_user.id).
            paginate(page: current_page, per_page: PAGE_SIZE, total_entries: total_entries).
            order("followers.created_at DESC").pluck(:following_id)

          user_following_scope = ::User.where(id: following_user_ids).
            includes(:profile).
            filter_spam_for(current_user)

          user_following_scope.to_a # this similarly can be removed later, we just need to force the query to run
        end

        e.clean do |val|
          val&.map(&:id).sort || []
        end

        e.compare do |control, candidate|
          control.map(&:id).sort == candidate.map(&:id).sort
        end
      end

      GitHub::PrefillAssociations.prefill_batch_method(followings, :followed_by?, current_user)

      render "users/tabs/following/index", locals: {
        followings: followings,
        layout_data: Profiles::User::LayoutData.preload(
          profile_user: this_user,
          viewer: current_user,
          active_tab: :following,
        ),
      }
    end

    def instrument_hydro
      GlobalInstrumenter.instrument(
        "user_profile.page_view",
        has_organization_memberships: this_user.organizations.any?,
        profile_user: this_user,
        profile_viewer: current_user,
        scoped_org_id: scoped_organization&.id,
        selected_tab: :FOLLOWING,
      )
    end

    def record_profile_stats
      return yield unless logged_in? && this_user && !this_user.organization?

      before = Time.now
      yield
      duration = Time.now - before

      tags = ProfilesController::ShowProfileStats.tags(
        activity_overview_rendered: activity_overview_enabled?,
        subject_user: this_user,
        viewer: current_user,
      )

      GitHub.dogstats.distribution("user.profile.following.request", duration * 1000, tags: tags)
    end

    def require_user
      if this_user.nil?
        render_404
      elsif this_user.organization?
        redirect_to user_path(this_user)
      end
    end

    def target_for_conditional_access
      return :no_target_for_conditional_access unless this_user.present? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      this_user
    end
  end
end
