# typed: true
# frozen_string_literal: true

class InProductMessagingClickController < ApplicationController
  include ApplicationController::VerifiedFetchDependency

  depends_on_clusters ApplicationRecord::Domain::Users,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities

  before_action :login_required
  allow_verified_fetch only: [:new]

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = %w[
    InProductMessagingClickController#create
  ].freeze

  DESTINATION_PATHS = {
    "nudge_organization_win_cb_users_back_credit_assign_seats" => "/organizations/:organization_login/settings/copilot/seat_management",
    "nudge_organization_win_cb_users_back_credit" => "/github-copilot/purchase?organization=:organization_login",
    "nudge_enterprise_win_cb_users_back_credit" => "/github-copilot/purchase?enterprise=:business_slug",
    "nudge_enterprise_win_cb_users_back_credit_assign_seats" => "/enterprises/:business_slug/enterprise_licensing/copilot?tab=organizations",
    "dfd_new_tasks_cb_activate_cb" => "/enterprises/:business_slug/trial_activations",
    "dfd_new_tasks_org_create_org" => "/enterprises/:business_slug/organizations/new",
    "dfd_new_tasks_repo_create_repo" => "/organizations/:enterprise_oldest_organization_slug/repositories/new",
    "dfd_new_tasks_code_add_code" => "/:org_with_oldest_repo_slug/:oldest_repo_slug",
    "dfd_new_tasks_repo_enable_ghas" => "/:org_with_oldest_repo_slug/:oldest_repo_slug/security",
    "cb_settings_organizations_new_tasks_raf" => "/organizations/:organization_login/settings/member_feature_requests",
    "dashboard_notify_users_cb_seat_nudge" => "https://docs.github.com/en/copilot/how-tos/set-up/set-up-for-self#2-install-the-copilot-extension-for-your-ide",
    "nudge_enterprise_preview_spark_and_cli" => "/enterprises/:business_slug/ai-controls/copilot",
    "nudge_enterprise_preview_loops" => "/enterprises/:business_slug/ai-controls/copilot",
  }.freeze

  # GET /in-product-messaging/click-and-redirect
  # Trackis a click in the system of record and redirects to destination URL based on key lookup
  def show
    notice = params[:notice]
    destination_key = params[:destination_key]
    group = params[:group].present? ? params[:group].to_sym : nil
    business_id = params[:business_id].present? ? params[:business_id] : nil
    organization_id = params[:organization_id].present? ? params[:organization_id] : nil

    if destination_key.present? && DESTINATION_PATHS.key?(destination_key)
      url = DESTINATION_PATHS[destination_key]

      if url.include?(":business_slug")
        business_slug = Business.find_by(id: business_id)&.slug

        if business_slug.present?
          url = url.gsub(":business_slug", business_slug)
        else
          url = "https://github.com"
        end
      end

      if url.include?(":organization_login")
        organization_login = Organization.find_by(id: organization_id)&.display_login
        if organization_login.present?
          url = url.gsub(":organization_login", organization_login)
        else
          url = "https://github.com"
        end
      end

      if url.include?(":enterprise_oldest_organization_slug")
        oldest_org = Organization
          .includes(business_membership: [:business])
          .where(business_organization_memberships: { business_id: business_id })
          .order(created_at: :asc)
          .first

        enterprise_oldest_organization_slug = oldest_org.display_login if oldest_org.present?

        if enterprise_oldest_organization_slug.present?
          url = url.gsub(":enterprise_oldest_organization_slug", enterprise_oldest_organization_slug)
        else
          url = "https://github.com"
        end
      elsif url.include?(":org_with_oldest_repo_slug")
        oldest_repo, org_with_oldest_repo = ::Organization
          .includes(business_membership: [:business])
          .where(business_organization_memberships: { business_id: business_id })
          .filter { |org| org.created_at + 1.day <= Time.current }
          .flat_map { |org| org.repositories_associated_with(current_user).map { |repo| [repo, org] } }
          .sort_by { |repo, _| repo.created_at }
          .first

        if oldest_repo.present? && org_with_oldest_repo.present?
          oldest_repo_slug = oldest_repo.name
          org_with_oldest_repo_slug = org_with_oldest_repo.display_login

          url = url.gsub(":oldest_repo_slug", oldest_repo_slug)
          url = url.gsub(":org_with_oldest_repo_slug", org_with_oldest_repo_slug)
        end
      end
    else
      url = "https://github.com"
    end

    if notice.present?
      # Use connected write role to avoid replication lag
      ActiveRecord::Base.connected_to(role: :writing) do
        current_user.track_nudge_click(id: notice, group: group, enterprise_id: business_id)
      end
    end

    redirect_to url
  end

  # POST /track-nudge-click
  def create
    id = params[:id]

    return render json: { success: false }, status: :bad_request unless id.present?

    group = params[:group]&.to_sym
    org_id = params[:org_id].present? ? params[:org_id] : nil
    enterprise_id = params[:enterprise_id].present? ? params[:enterprise_id] : nil

    ActiveRecord::Base.connected_to(role: :writing) do
      current_user.track_nudge_click(id: id, group: group, org_id: org_id, enterprise_id: enterprise_id)
    end

    render json: { success: true }
  end

  private

  # Safe because :login_required
  def resource_for_conditional_access
    # Ensure we have a resource that supports conditional access
    return :no_resource_for_conditional_access unless current_user  # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    current_user
  end

  # Safe because :login_required
  def target_for_conditional_access
    # Target should always be the current user for in-product messaging
    current_user || :no_target_for_conditional_access  # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
