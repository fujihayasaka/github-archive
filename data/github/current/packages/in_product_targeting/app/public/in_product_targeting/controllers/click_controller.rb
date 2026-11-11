# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module Controllers
    class ClickController < ApplicationController
      include ApplicationController::VerifiedFetchDependency
      include InProductTargeting::Controllers::Concerns::UtmParams

      depends_on_clusters ApplicationRecord::Domain::Users,
        ApplicationRecord::Mysql1,
        ApplicationRecord::Collab,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Repositories

      before_action :login_required
      allow_verified_fetch only: [:new]

      CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = T.let(%w[
        InProductTargeting::Controllers::ClickController#create
      ].freeze, T::Array[String])

      GITHUB_FALLBACK_URL = T.let("https://github.com".freeze, String)

      # Controller that unmatched paths fall through to via the catch-all route.
      # When a destination route is not present in the current environment, the
      # path resolves to this controller instead of a real handler.
      ROUTING_ERROR_CONTROLLER = T.let("routing_error".freeze, String)

      DESTINATION_PATHS = T.let({
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
        "ipm_copilot_cli_enterprise_nudge" => "/enterprises/:business_slug/ai-controls/copilot",
        "ipm_copilot_cli_organization_nudge" => "/organizations/:organization_login/settings/copilot/policies",
        "ipm_accelerate_dashboard_copilot_cli_enabled_nudge" => "https://github.com/github/copilot-cli?tab=readme-ov-file#-getting-started",
        "copilot_coding_agent_enterprise_nudge" => "/enterprises/:business_slug/ai-controls/agents/policies",
        "secure_ipm_security_risk_assessment_v2" => "/orgs/:organization_login/security/assessments",
      }.freeze, T::Hash[String, String])

      # GET /in-product-messaging/click-and-redirect
      # Tracks a click in the system of record and redirects to destination URL based on key lookup
      sig { void }
      def show
        notice = params[:notice]
        destination_key = params[:destination_key]
        group = params[:group].present? ? params[:group].to_sym : nil
        business_id = params[:business_id].present? ? params[:business_id] : nil
        organization_id = params[:organization_id].present? ? params[:organization_id] : nil
        organization_login_param = params[:organization_login].presence
        business_slug_param = params[:business_slug].presence

        if destination_key.present? && DESTINATION_PATHS.key?(destination_key)
          url = T.must(DESTINATION_PATHS[destination_key])

          if url.include?(":business_slug")
            business_slug =
              if valid_business_slug_param?(business_slug_param)
                business_slug_param
              else
                slug = Business.find_by(id: business_id)&.slug
                if slug.nil?
                  slug = Organization.find_by(id: organization_id)&.business&.slug
                end
                slug
              end

            if business_slug.present?
              url = url.gsub(":business_slug", business_slug)
            else
              url = GITHUB_FALLBACK_URL
            end
          end

          if url.include?(":organization_login")
            organization_login =
              if valid_organization_login_param?(organization_login_param)
                organization_login_param
              else
                Organization.find_by(id: organization_id)&.display_login
              end

            if organization_login.present?
              url = url.gsub(":organization_login", organization_login)
            else
              url = GITHUB_FALLBACK_URL
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
              url = GITHUB_FALLBACK_URL
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
          url = GITHUB_FALLBACK_URL
        end

        # Guard against redirecting to a destination route that does not exist in
        # the current environment. Without this, the click is tracked and a 302 is
        # issued, but the follow-up request lands on the routing-error handler
        # (rendered as a hard crash in development) instead of a usable page.
        url = GITHUB_FALLBACK_URL unless destination_available?(url)

        if notice.present?
          # Use connected write role to avoid replication lag
          ActiveRecord::Base.connected_to(role: :writing) do
            InProductTargeting::NudgeMemory.new(T.must(current_user)).save_a_copy_of_click_analytics_to_dotcom(id: notice, group: group, org_id: organization_id, enterprise_id: business_id)
          end
        end

        redirect_to add_utm_params(url)
      end

      # POST /track-nudge-click
      sig { void }
      def create
        id = params[:id]

        return render json: { success: false }, status: :bad_request unless id.present?

        group = params[:group]&.to_sym
        org_id = params[:org_id].present? ? params[:org_id] : nil
        enterprise_id = params[:enterprise_id].present? ? params[:enterprise_id] : nil

        ActiveRecord::Base.connected_to(role: :writing) do
          InProductTargeting::NudgeMemory.new(T.must(current_user)).save_a_copy_of_click_analytics_to_dotcom(id: id, group: group, org_id: org_id, enterprise_id: enterprise_id)
        end

        render json: { success: true }
      end

      private

      # Safe because :login_required
      sig { returns(T.any(Symbol, User)) }
      def resource_for_conditional_access
        # Ensure we have a resource that supports conditional access
        return :no_resource_for_conditional_access unless current_user  # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
        T.must(current_user)
      end

      # Safe because :login_required
      sig { returns(T.any(Symbol, User)) }
      def target_for_conditional_access
        # Target should always be the current user for in-product messaging
        current_user || :no_target_for_conditional_access  # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      end

      sig { params(value: T.nilable(String)).returns(T::Boolean) }
      def valid_organization_login_param?(value)
        return false if value.blank?
        value.length <= User::LOGIN_MAX_LENGTH && User::LOGIN_REGEX.match?(value)
      end

      sig { params(value: T.nilable(String)).returns(T::Boolean) }
      def valid_business_slug_param?(value)
        return false if value.blank?
        value.length <= Business::MAX_SLUG_LENGTH && Business::SLUG_REGEX.match?(value)
      end

      # Returns true when the destination URL points to a route that can actually
      # be served. External (absolute) URLs are assumed reachable. Internal paths
      # are checked against the route set; a path that resolves to the catch-all
      # routing-error controller (or fails recognition) is treated as unavailable.
      sig { params(url: String).returns(T::Boolean) }
      def destination_available?(url)
        return true unless url.start_with?("/")

        path = T.must(url.split(/[?#]/).first)
        recognized = Rails.application.routes.recognize_path(path)
        recognized[:controller] != ROUTING_ERROR_CONTROLLER
      rescue ActionController::RoutingError, URI::InvalidURIError
        false
      end
    end
  end
end
