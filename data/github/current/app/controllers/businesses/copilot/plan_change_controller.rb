# typed: strict
# frozen_string_literal: true

class Businesses::Copilot::PlanChangeController < Businesses::BusinessController
  extend T::Sig

  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include ApplicationHelper

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:show]

  class InvalidPlanTypeError < StandardError; end

  allow_verified_fetch only: [:show]

  before_action :validate_plan_type, only: [:show]

  sig { void }
  def show
    respond_to do |format|
      format.html_fragment do
        orgs = Organization.where(id: params[:organizations].map(&:to_i))
        return render_404 if orgs.empty?

        options = {
          business: T.let(this_business, ::Business),
          organizations: orgs.to_a,
        }

        if params[:reenable] == "true"
          render Copilot::OrgEnablement::PlanReenableComponent.new(**options.merge({ copilot_plan: params[:copilot_plan] })), layout: false
          return
        end

        render component_for(params[:copilot_plan]).new(**options), layout: false
      end
    end
  end

  private

  sig do
    params(copilot_plan: String)
    .returns(
      T.any(
        T.class_of(Copilot::OrgEnablement::PlanUpgradeComponent),
        T.class_of(Copilot::OrgEnablement::PlanDowngradeComponent),
        T.class_of(Copilot::OrgEnablement::PlanDisableComponent)
      )
    )
  end
  def component_for(copilot_plan)
    case copilot_plan
    when "business"
      Copilot::OrgEnablement::PlanDowngradeComponent
    when "enterprise"
      Copilot::OrgEnablement::PlanUpgradeComponent
    when "disable"
      Copilot::OrgEnablement::PlanDisableComponent
    else
      # This really can't happen, due to the before_action checks, but Sorbet needs it
      raise InvalidPlanTypeError.new("Invalid copilot plan: #{copilot_plan}")
    end
  end

  sig { void }
  def permitted_params
    params.permit(:organizations, :copilot_plan, :reenable)
  end

  sig { void }
  def validate_plan_type
    render plain: "Invalid plan type", status: :unprocessable_entity and return unless %w[business enterprise disable].include?(params[:copilot_plan])
  end
end
