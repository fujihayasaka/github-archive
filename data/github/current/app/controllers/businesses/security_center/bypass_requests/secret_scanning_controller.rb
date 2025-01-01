# typed: strict
# frozen_string_literal: true

module Businesses
  module SecurityCenter
    module BypassRequests
      class SecretScanningController < AbstractSecurityCenterController
        include SecretScanningControllerHelper

        skip_before_action :cap_pagination, unless: :robot?

        before_action :check_advanced_security_status
        before_action :security_center_required
        before_action :check_feature_flag_enabled

        include ::SecretScanning::Constants
        include Repos::RulesHelper
        include ::SecretScanning::Features::FeatureFlagHelper

        depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::Repositories,
        ApplicationRecord::RepositoriesPushes,
        ApplicationRecord::Mysql5,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Mysql2,
        ApplicationRecord::Collab,
        ApplicationRecord::Copilot,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Billing,
        ApplicationRecord::Configurations,
        ApplicationRecord::Spokes,
        ApplicationRecord::Iam,
        only: [:index, :requesters, :approvers]

        depends_on_clusters  ApplicationRecord::SecurityOverviewAnalytics,
        ApplicationRecord::Notify,
        optional: true,
        only: [:index]

        sig { returns(String) }
        def self.react_bundle_name
          "delegated-bypass"
        end

        sig { void }
        def index
          filter = {
            approver: params[:approver],
            requester: params[:requester],
            time_period: params[:time_period],
            request_status: params[:request_status],
            repository: params[:repository],
            organization: params[:organization],
          }
          if can_view_request_list?
            payload = rules_bypass_requests_payload(
              viewing_source: current_business,
              filter: filter,
              page: params[:page].to_i,
             base_exemption_url: "../../../secret_scanning/exemptions/",
            request_types: [::SecretScanning::Constants::EXEMPTION_REQUEST_TYPE],
            repo_exemptions_base_url_suffix: "secret_scanning/exemptions/"
            )
            payload["unauthorizedUser"] = false
          else
            _, source_type = source_payload_and_type(current_business)
            # Create the payload with camelized keys to avoid a slow call to Repos::ReactPayload::camelize_keys
            payload = {
              filter: filter,
              exemptionRequests: [],
              hasMoreRequests: false,
              sourceType: source_type,
              unauthorizedUser: true,
            }
          end
          render_react_app(
            payload: payload,
            app_payload_generator: -> { Exemptions::ReactPayload.app_payload(current_business, ::SecretScanning::ExemptionConstants::EXEMPTION_REQUEST_TYPE) },
            title: "Security · Secret Scanning Push Protection Bypass Requests · #{current_business.name}",
            page_data: {
              sidebar: :code_security,
              selected_link: :business_security_center_bypass_requests_secret_scanning,
            },
            layout: "layouts/react_business",
            disable_ssr: true,
          )
        end

        sig { void }
        def approvers # rubocop:todo GitHub/UseRestfulActions
          approvers = can_view_request_list? ? RulesEngine::Suggestions.bypass_requests_approvers_for(current_business, ::SecretScanning::ExemptionConstants::EXEMPTION_REQUEST_TYPE) : []
          render json: helpers.filter_suggestions(approvers)
        end

        sig { void }
        def requesters # rubocop:todo GitHub/UseRestfulActions
          requesters = can_view_request_list? ? RulesEngine::Suggestions.bypass_requests_requesters_for(current_business, ::SecretScanning::ExemptionConstants::EXEMPTION_REQUEST_TYPE) : []
          render json: helpers.filter_suggestions(requesters)
        end

        private

        sig { override.returns(T.nilable(Symbol)) }
        def authorized_orgs_actions
          nil
        end

        sig { void }
        def check_advanced_security_status
          if this_business.advanced_security_products_bundled?
            render_404 unless this_business.advanced_security_purchased?
          else
            render_404 unless this_business.secret_protection_purchased?
          end
        end

        sig { returns(T::Boolean) }
        def can_view_request_list?
          ::SecurityProduct::Permissions::BusinessAuthz.new(this_business, actor: current_user).can_view_enterprise_bypass_requests_list?
        end

        sig { void }
        def check_feature_flag_enabled
          render_404 unless feature_flag_enabled_in_hierarchy?(this_business, FeatureFlags::ENTERPRISE_DELEGATED_BYPASS)
        end
      end
    end
  end
end
