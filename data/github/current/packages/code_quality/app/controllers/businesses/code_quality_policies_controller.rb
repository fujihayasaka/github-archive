# typed: true
# frozen_string_literal: true

class Businesses::CodeQualityPoliciesController < Businesses::BusinessController
  include ApplicationController::VerifiedFetchDependency # validates verifiedFetch requests made from react app
  include ApplicationController::JsonDependency # enables JSON body parsing

  before_action :view_or_modify_code_quality_permission_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :code_quality_available_required
  before_action :try_parse_json_params, only: [:update_code_quality_enablement, :update_code_quality_availability, :update_org_code_quality_availability]

  allow_verified_fetch only: [:update_code_quality_enablement, :update_code_quality_availability, :update_org_code_quality_availability]

  javascript_bundle :settings

  track_latency_slo "p99-ui-request", 2000
  track_latency_slo "p50-ui-request", 500
  track_availability_slo "ui-request"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    only: [:index, :organizations]

  depends_on_clusters ApplicationRecord::Billing, optional: true,
    only: [:index, :organizations]

  def index
    access_policy_config = CodeQualityAccessPolicyConfig.new(this_business)

    respond_with_react(
      app_name: "code-quality",
      payload: EnterpriseCodeQualityPoliciesPayload.new(
        enterprise_id: this_business.id,
        enterprise_slug: this_business.slug,
        repo_admins_can_modify_enablement: this_business.repo_admins_can_modify_code_quality_enablement?,
        code_quality_availability: code_quality_availability_value(access_policy_config),
        selected_org_ids: access_policy_config.code_quality_selected_access_allowed_entities,
      ),
      title: "Code Quality · #{this_business.name}",
      page_data: { selected_link: :business_code_quality_policies, sidebar: :policies },
      layout: "react_business",
    )
  end

  # Payload class for the React app
  class EnterpriseCodeQualityPoliciesPayload < ReactPayload::Base
    def route_id
      "enterpriseCodeQualityPoliciesRoute"
    end

    def initialize(enterprise_id:, enterprise_slug:, repo_admins_can_modify_enablement:, code_quality_availability:, selected_org_ids:)
      @enterprise_id = enterprise_id
      @enterprise_slug = enterprise_slug
      @repo_admins_can_modify_enablement = repo_admins_can_modify_enablement
      @code_quality_availability = code_quality_availability
      @selected_org_ids = selected_org_ids
    end

    def payload
      {
        enterprise_id: @enterprise_id,
        enterprise_slug: @enterprise_slug,
        repo_admins_can_modify_enablement: @repo_admins_can_modify_enablement,
        code_quality_availability: @code_quality_availability,
        selected_org_ids: @selected_org_ids,
      }
    end
  end

  def update_code_quality_enablement # rubocop:todo GitHub/UseRestfulActions
    setting_for_repo_admins = code_quality_enablement_params[:all_repo_admins]

    case setting_for_repo_admins
    when "allowed"
      this_business.allow_repo_admins_to_modify_code_quality_enablement(actor: current_user)
    when "not_allowed"
      this_business.disallow_repo_admins_to_modify_code_quality_enablement(actor: current_user)
    else
      render json: { error: "You provided an invalid input value. Please try again." }, status: :unprocessable_entity
      return
    end

    render json: {
      message: "Policy changes saved.",
      # Intentionally re-query the DB to confirm the update was persisted
      repo_admins_can_modify_enablement: this_business.repo_admins_can_modify_code_quality_enablement?,
    }, status: :ok
  end

  def update_code_quality_availability # rubocop:todo GitHub/UseRestfulActions
    availability_setting = code_quality_availability_params[:code_quality_availability]
    access_policy_config = CodeQualityAccessPolicyConfig.new(this_business)

    case availability_setting
    when "all"
      access_policy_config.allow_members_to_enable_code_quality(actor: current_user)
      log_availability_change(availability_setting)
    when "selected"
      access_policy_config.allow_selected_members_to_enable_code_quality(actor: current_user)
      log_availability_change(availability_setting)
    when "none"
      access_policy_config.disallow_members_to_enable_code_quality(actor: current_user)
      log_availability_change(availability_setting)
    else
      render json: { error: "You provided an invalid input value. Please try again." }, status: :unprocessable_entity
      return
    end

    render json: {
      message: "Policy changes saved.",
      code_quality_availability: code_quality_availability_value(access_policy_config),
    }, status: :ok
  end

  def update_org_code_quality_availability # rubocop:todo GitHub/UseRestfulActions
    org_id = org_code_quality_availability_params[:org_id]
    allowed = org_code_quality_availability_params[:allowed]

    # Validate org_id is a valid integer
    org_id_int = ActiveModel::Type::Integer.new.cast(org_id)
    if org_id_int.nil? || org_id_int.to_s != org_id.to_s.strip
      render json: { error: "Invalid organization ID. Please try again." }, status: :unprocessable_entity
      return
    end

    organization = this_business.organizations.find_by(id: org_id_int)

    if organization.nil?
      render json: { error: "Organization not found. Please select an organization and retry." }, status: :not_found
      return
    end

    unless [true, false, "true", "false"].include?(allowed)
      render json: { error: "You provided an invalid input value. Please try again." }, status: :unprocessable_entity
      return
    end

    allowed_bool = allowed.to_s == "true"
    org_config = CodeQualityAccessPolicyConfig.new(organization)
    org_config.set_code_quality_entity_policy(allowed: allowed_bool, actor: current_user)
    log_org_policy_change(organization, allowed_bool)

    render json: {
      message: "Policy changes saved.",
      org_id: org_id.to_i,
      allowed: allowed_bool,
    }, status: :ok
  end

  def organizations # rubocop:todo GitHub/UseRestfulActions
    page = (params[:page] || 1).to_i
    per_page = 25
    query = params[:query].to_s.strip

    orgs_scope = this_business.organizations.order(:login)
    orgs_scope = orgs_scope.where("login LIKE ?", "%#{query}%") if query.present?

    total_count = orgs_scope.count
    organizations = orgs_scope.offset((page - 1) * per_page).limit(per_page)

    access_policy_config = CodeQualityAccessPolicyConfig.new(this_business)
    selected_org_ids = access_policy_config.code_quality_selected_access_allowed_entities

    orgs_data = organizations.map do |org|
      {
        id: org.id,
        login: org.display_login,
        avatar_url: org.primary_avatar_url,
        allowed: selected_org_ids.include?(org.id),
      }
    end

    render json: {
      organizations: orgs_data,
      total_count: total_count,
      page: page,
      per_page: per_page,
      total_pages: (total_count.to_f / per_page).ceil,
    }, status: :ok
  end

  private

  def view_or_modify_code_quality_permission_required
    render_404 unless this_business&.owner?(current_user)
  end

  def code_quality_available_required
    render_404 unless CodeQuality.available?(this_business)
  end

  def code_quality_availability_value(access_policy_config)
    if access_policy_config.all_members_can_enable_code_quality?
      "all"
    elsif access_policy_config.selected_members_can_enable_code_quality?
      "selected"
    elsif access_policy_config.no_members_can_enable_code_quality?
      "none"
    else
      "all" # Default fallback
    end
  end

  def code_quality_enablement_params
    params.slice(:all_repo_admins).permit(:all_repo_admins)
  end

  def code_quality_availability_params
    params.slice(:code_quality_availability).permit(:code_quality_availability)
  end

  def org_code_quality_availability_params
    params.slice(:org_id, :allowed).permit(:org_id, :allowed)
  end

  def log_availability_change(availability_setting)
    # Stub for audit logging - implement with proper audit log integration
    # Example: AuditLog.record(actor: current_user, action: "code_quality.availability_changed", target: this_business, data: { availability: availability_setting })
  end

  def log_org_policy_change(organization, allowed)
    # Stub for audit logging - implement with proper audit log integration
    # Example: AuditLog.record(actor: current_user, action: "code_quality.org_policy_changed", target: organization, data: { allowed: allowed })
  end
end
