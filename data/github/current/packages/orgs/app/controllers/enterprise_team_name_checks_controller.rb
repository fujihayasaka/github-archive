# typed: strict
# frozen_string_literal: true

class EnterpriseTeamNameChecksController < Businesses::BusinessController
  include BusinessTeamHandlers

  before_action :business_owner_required
  before_action :enterprise_teams_enabled_required

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:show]

  sig { void }
  def show
    name = params[:teamName]
    old_team_slug = params[:teamOldSlug]
    old_team_name = params[:teamOldName]

    # Name is empty
    if name.blank?
      return render json: { team: name, error: "name cannot be empty" }, status: 422
    end

    # Name is too long
    if name.length > BusinessTeam::MAX_TEAM_NAME_LENGTH
      return render json: {
        team: name,
        error: "name is too long, maximum length is #{BusinessTeam::MAX_TEAM_NAME_LENGTH} characters"
      }, status: 422
    end

    # Name has unsupported characters
    unless GitHub::UTF8.valid_unicode3?(name)
      return render json: { team: name, error: "contains unsupported characters" }, status: 422
    end

    # Name has not been modified
    if old_team_name && old_team_name == name
      return render json: { message: "unchanged" }
    end

    # Name is already taken by another enterprise team within the same enterprise
    if old_team_slug && name_taken?(name, old_team_slug)
      return render json: { team: name, error: "is already taken" }, status: 422
    end

    render json: { team: name }
  end

  private

  sig { params(name: String, old_team_slug: String).returns(T::Boolean) }
  def name_taken?(name, old_team_slug)
    slug = BusinessTeam.to_model_slug(old_team_slug)
    current_business.business_teams.where(name: name).where.not(slug: slug).any?
  end

  sig { void }
  def enterprise_teams_enabled_required
    render_404 unless BusinessTeam.enabled_for_enterprise?(business: current_business)
  end
end
