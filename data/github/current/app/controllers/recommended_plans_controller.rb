# typed: true
# frozen_string_literal: true

class RecommendedPlansController < ApplicationController
  layout "layouts/signups"

  stylesheet_bundle "site"
  stylesheet_bundle "signup"
  stylesheet_bundle "recommended_plans"

  before_action :disable_color_modes
  before_action :login_required

  def new
    GitHub.dogstats.increment("signup.recommended_plans", tags: ["step:welcome"])

    validation_errors = session.dig("recommended_plan", "validation_errors")
    session["recommended_plan"] = { "next_step" => "tools", "validation_errors" => validation_errors }

    render "recommended_plans/welcome"
  end

  def create
    session["recommended_plan"]&.deep_merge!(plan_suggestion_params.to_h)

    case session.dig("recommended_plan", "next_step")
    when "tools"
      # check that the user has selected at least one seat option
      session["recommended_plan"]["validation_errors"] = nil
      if session.dig("recommended_plan", "size").blank?
        session["recommended_plan"]["validation_errors"] = "size"
        return redirect_to signup_welcome_path
      end
      GitHub.dogstats.increment("signup.recommended_plans", tags: ["step:tools"])
      session["recommended_plan"]["next_step"] = "finish"

      render "recommended_plans/tools"
    when "finish"
      GitHub.dogstats.increment("signup.recommended_plans", tags: ["step:finish"])

      suggested_plan = suggest_plan
      session.delete("recommended_plan")

      render "recommended_plans/plans", locals: {
        suggested_plan: suggested_plan
      }
    else
      redirect_to signup_welcome_path
    end
  end

  private

  def suggest_plan
    education_type = session.dig("recommended_plan", "education_type").presence
    team_size      = session.dig("recommended_plan", "size")
    tools          = session.dig("recommended_plan", "tools") || []

    PlanSuggestion.new(
      user: current_user,
      team_size: team_size,
      education_type: education_type,
      tools: tools).recommend_plan
  end

  def plan_suggestion_params
    params.fetch(:suggested_plan, {}).permit(:size, :education_type, tools: [])
  end

  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    current_user
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
