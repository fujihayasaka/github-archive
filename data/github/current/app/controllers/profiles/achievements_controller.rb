# typed: true
# frozen_string_literal: true

module Profiles
  class AchievementsController < Achievements::BaseController
    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Collab,
      ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::Repositories,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Configurations,
      ApplicationRecord::Ballast,
      ApplicationRecord::Spokes,
      only: [:show]

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Collab,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Configurations,
      ApplicationRecord::Repositories,
      only: [:index]

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:index, :show], optional: true

    before_action :ensure_has_achievements, only: :index
    before_action :ensure_valid_open_achievement, only: :index
    after_action :mark_achievements_as_seen, only: :index
    after_action :instrument_hydro, only: :index
    before_action :require_achieved_tiers, only: :show
    before_action :require_xhr, only: :show

    def index
      layout_data = Profiles::User::LayoutData.preload(
        profile_user: this_user,
        viewer: current_user,
        active_tab: :achievements,
      )
      visible_models = if open_achievement&.description_needs_unlocking_model?
        visible_unlocking_models([open_achievement.unlocking_model])
      else
        []
      end

      render "users/tabs/achievements/index", locals: {
        user: this_user,
        achievements: highest_tier_achievements,
        open_achievement: open_achievement,
        richweb_attributes: Profiles::User::RichwebAttributes.build(
          layout_data, open_achievement, visible_models,
        ),
        layout_data: layout_data,
      }
    end

    def show
      visible_models = visible_unlocking_models(achieved_tiers.map(&:unlocking_model))

      render(Profiles::User::Achievements::ShowComponent.new(
        profile_user: this_user,
        achievements: achieved_tiers,
        visible_models: visible_models,
        is_hovercard: params[:hovercard] == "1",
      ), layout: false)
    end

    private

    memoize def open_achievement
      return nil unless params.has_key?(:achievement)

      achievable = Achievable.with_slug(params[:achievement])
      return nil unless achievable

      highest_tier_achievements.find { |achievement| achievement.achievable == achievable }
    end

    def ensure_has_achievements
      render_404 if highest_tier_achievements.none?
    end

    def ensure_valid_open_achievement
      return unless params.has_key?(:achievement)

      render_404 unless open_achievement
    end

    def mark_achievements_as_seen
      return unless logged_in?
      return unless this_user == current_user

      # Note: this query could become large if we add many more achievables. If so, we may need to batch these into
      # slices.
      clauses = highest_tier_achievements.map do |achievement|
        this_user.achievements
          .where(
            "achievable_slug = :achievable_slug AND tier <= :tier",
            achievable_slug: achievement.achievable_slug,
            tier: achievement.tier,
          )
      end
      unseen_achievement_ids = clauses.inject { |scope0, scope1| scope0.or(scope1) }.pluck(:id)

      return if unseen_achievement_ids.none?
      seen_time = Time.now

      after_response do
        ActiveRecord::Base.connected_to(role: :writing) do
          Achievement.where(id: unseen_achievement_ids).update_all(seen_at: seen_time)
        end
      end
    end

    def instrument_hydro
      GlobalInstrumenter.instrument(
        "user_profile.page_view",
        has_organization_memberships: this_user.organizations.any?,
        profile_user: this_user,
        profile_viewer: current_user,
        scoped_org_id: nil,
        selected_tab: :ACHIEVEMENTS,
      )
    end
  end
end
