# typed: strict
# frozen_string_literal: true

class Businesses::AiControls::SkillsController < Businesses::BusinessController
  include ApplicationController::JsonDependency
  include Businesses::AiControls::Concerns::SkillsFetcher

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot

  before_action :ai_controls_enabled?
  before_action :ai_controls_read_required

  sig { void }
  def index
    skills = fetch_skills_data

    render json: {
      skills: skills
    }
  end

  private

  sig { void }
  def ai_controls_enabled?
    render_404 unless helpers.show_ai_controls?(this_business)
  end

  sig { void }
  def ai_controls_read_required
    render_404 unless this_business&.actor_can_read_enterprise_ai_controls?(current_user)
  end
end
