# typed: true
# frozen_string_literal: true

class RecommendedPlansController < ApplicationController
  layout "layouts/signups"

  stylesheet_bundle "site"
  stylesheet_bundle "signup"
  stylesheet_bundle "recommended_plans"

  javascript_bundle "signup-redesign"

  before_action :disable_color_modes
  before_action :login_required

  def new
    GitHub.dogstats.increment("signup.recommended_plans", tags: ["step:welcome"])

    missing_required_fields = session.dig("recommended_plan", "missing_required_fields") || []
    validation_errors = Set.new(missing_required_fields.map(&:to_sym))

    session["recommended_plan"] = { "next_step" => "purpose" }

    render "recommended_plans/welcome", locals: { validation_errors: validation_errors }
  end

  def create
    session["recommended_plan"]&.deep_merge!(plan_suggestion_params.to_h)

    next_step = session.dig("recommended_plan", "next_step")
    case next_step
    when "purpose"
      missing_required_fields = required_fields.select { |field| session["recommended_plan"][field].blank? }

      if missing_required_fields.any?
        session["recommended_plan"]["missing_required_fields"] = missing_required_fields
        return redirect_to signup_welcome_path
      end

      GitHub.dogstats.increment("signup.recommended_plans", tags: ["step:#{next_step}"])
      session["recommended_plan"]["next_step"] = "finish"

      render "recommended_plans/purpose", locals: { show_validation_message: false }
    when "finish"
      purpose = session.dig("recommended_plan", "purpose") || []
      if purpose.length > 2
        return render "recommended_plans/purpose", locals: { show_validation_message: true }
      end

      GitHub.dogstats.increment("signup.recommended_plans", tags: ["step:#{next_step}"])

      suggested_plan = suggest_plan
      session.delete("recommended_plan")

      if current_user.feature_enabled?(:nux_skip_plan_recommendation)
        redirect_to dashboard_path
      else
        render "recommended_plans/plans", locals: {
          suggested_plan: suggested_plan
        }
      end
    else
      redirect_to signup_welcome_path
    end
  end

  private

  def suggest_plan
    user_self_description = session.dig("recommended_plan", "user_self_description").presence
    team_size      = session.dig("recommended_plan", "size")
    purpose        = session.dig("recommended_plan", "purpose") || []

    PlanSuggestion.new(
      user: current_user,
      team_size: team_size,
      user_self_description: user_self_description,
      purpose: purpose
    ).recommend_plan
  end

  def plan_suggestion_params
    params.fetch(:suggested_plan, {}).permit(:size, :user_self_description, purpose: [])
  end

  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    current_user
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end

  def required_fields
    %w[user_self_description size]
  end
end
