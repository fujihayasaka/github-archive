# typed: strict
# frozen_string_literal: true

class Copilot::PlanPurchaseController < ApplicationController
  extend T::Sig

  before_action :login_required
  before_action :dotcom_required
  before_action :ensure_feature_flag_enabled
  before_action :ensure_plan_target

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Copilot,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Ballast

  sig { void }
  def new
    # Enables us to set a custom breadcrumb for the global nav.
    # TODO will we need to call set_context method in the plan comparison page? Or is set_context just for
    # global use?
    context_region_title("Purchase")
    render "copilot/purchase/new", layout: "copilot_plan_purchase"
  end

  private

  sig { void }
  def ensure_feature_flag_enabled
    return if current_user.feature_enabled?(:copilot_purchase_flow_refresh)
    render_404
  end

  sig { void }
  def ensure_plan_target
    # 404 if there isn't anything to purchase Copilot for.
    render_404 if !this_organization && !this_enterprise
  end

  sig { returns(T.nilable(::Organization)) }
  memoize def this_organization
    org = if params[:org]
      found = current_user.organizations.find_by_login(params[:org])
      found if found && found.adminable_by?(current_user)
    else
      current_user.organizations.find { |org| org.adminable_by?(current_user) }
    end

    org
  end

  sig { returns(T.nilable(::Business)) }
  memoize def this_enterprise
    businesses = current_user.businesses(membership_type: :admin)

    return businesses.find_by_slug(params[:enterprise]) if params[:enterprise].present?

    businesses.first
  end

  sig { returns(T.any(User, Symbol)) }
  def target_for_conditional_access
    logged_in? ? current_user : :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  sig { returns(T.any(User, Symbol)) }
  def resource_for_conditional_access
    # cap_bypass:to_fix - this controller is also targeting Business or Organization and should be considered in those actions
    logged_in? ? current_user : :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end
end
