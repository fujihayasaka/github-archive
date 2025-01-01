# typed: true
# frozen_string_literal: true

class Stafftools::AchievementsController < StafftoolsController
  include Profiles::Achievements::ControllerMethods

  layout "layouts/stafftools/user/overview"

  before_action :ensure_user_exists
  before_action :dotcom_required
  before_action :ensure_achievement_exists, only: [:edit, :update, :destroy]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    only: [:edit]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :edit], optional: true

  def index
    visible_models = this_user.highest_tier_achievements.flat_map do |achievement|
      achieved_tiers = this_user.achievements_for(achievement.achievable)
      GitHub::PrefillAssociations.prefill_associations(achieved_tiers, :unlocking_model)
      visible_unlocking_models(achieved_tiers.map(&:unlocking_model)).to_a
    end

    render Profiles::User::Achievements::Stafftools::IndexComponent.new(
      user: this_user,
      visible_models: visible_models,
    )
  end

  def new
    render Profiles::User::Achievements::Stafftools::UnlockingModelComponent.new(
      user: this_user,
      achievement: this_user.achievements.new(
        achievable_slug: params[:achievable_slug],
        tier: params[:tier],
        visibility: params[:visibility],
      ),
    )
  end

  def create
    achievement = this_user.achievements.new(achievement_params)

    if achievement.save
      flash[:notice] = "Achievement created!"
    else
      flash[:error] =
        "Achievement not created. Errors: #{achievement.errors.full_messages.to_sentence}."
    end

    redirect_to stafftools_user_achievements_path
  end

  def edit
    visible_models = visible_unlocking_models([achievement.unlocking_model])

    render Profiles::User::Achievements::Stafftools::UnlockingModelComponent.new(
      user: this_user,
      achievement: achievement,
      visible_models: visible_models,
    )
  end

  def update
    if achievement.update(achievement_params)
      flash[:notice] = "Achievement updated!"
      redirect_to stafftools_user_achievements_path
    else
      flash[:error] =
        "Achievement not updated. Errors: #{achievement.errors.full_messages.to_sentence}."
      redirect_to edit_stafftools_user_achievement_path(this_user, achievement)
    end
  end

  def destroy
    if achievement.destroy
      flash[:notice] = "Achievement destroyed!"
    else
      flash[:error] = "Achievement not destroyed."
    end

    redirect_to stafftools_user_achievements_path
  end

  private

  memoize def achievement
    this_user.achievements.find_by(id: params[:id])
  end

  def achievement_params
    params.
      require(:achievement).
      permit(:unlocking_model_type, :unlocking_model_id, :tier, :achievable_slug, :visibility)
  end

  def ensure_achievement_exists
    render_404 unless achievement
  end
end
