# typed: true
# frozen_string_literal: true

class Orgs::Settings::ModeratorsController < Orgs::Controller
  before_action :login_required
  before_action :organization_admin_required
  before_action :ensure_moderation_features_enabled
  before_action :ensure_moderator_exists, only: [:create, :destroy]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:index]

  def index
    render "orgs/settings/moderators/index", locals: {
      moderators: this_organization.moderators,
    }
  end

  def create
    result = this_organization.moderation.add_moderator(
      this_moderator,
      actor: current_user,
    )

    if result.success?
      flash[:notice] = "Successfully added #{result.moderator.ability_description} as a moderator"
    else
      flash[:error] = "Unable to add moderator: #{result.errors.to_sentence}"
    end

    redirect_to organization_settings_moderators_path(this_organization)
  end

  def destroy
    result = this_organization.moderation.remove_moderator(
      this_moderator,
      actor: current_user,
    )

    if result.success?
      flash[:notice] = "Successfully removed #{result.moderator.ability_description} as a moderator"
    else
      flash[:error] = "Unable to remove moderator: #{result.errors.to_sentence}"
    end

    redirect_to organization_settings_moderators_path(this_organization)
  end

  private

  def this_moderator # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @this_moderator if defined?(@this_moderator)
    @this_moderator = if params[:type] == "team"
      this_organization.teams.find_by(id: params[:id])
    else
      this_organization.members.find_by(id: params[:id])
    end
  end

  def ensure_moderation_features_enabled
    render_404 unless GitHub.organization_moderators_enabled?
  end

  def ensure_moderator_exists
    render_404 unless this_moderator.present?
  end
end
