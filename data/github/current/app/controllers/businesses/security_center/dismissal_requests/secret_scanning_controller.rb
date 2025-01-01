# typed: strict
# frozen_string_literal: true

module Businesses
  module SecurityCenter
    module DismissalRequests
      class SecretScanningController < AbstractSecurityCenterController
        include SecretScanningControllerHelper

        skip_before_action :cap_pagination, unless: :robot?

        before_action :check_secret_scanning_enabled
        before_action :security_center_required

        include Repos::RulesHelper

        depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::Repositories,
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
        only: [:index, :dismissal_request_requesters, :dismissal_request_approvers]

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
          required_repo_permission = :resolve_secret_scanning_alerts
          if can_view_request_list?
            payload = rules_bypass_requests_payload(
              viewing_source: current_business,
              filter: filter,
              page: params[:page].to_i,
              base_exemption_url: "../../../security/secret-scanning/",
              request_types: [::SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE],
              repo_exemptions_base_url_suffix: "security/secret-scanning/",
              required_repo_permission:,
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
            app_payload_generator: -> { Exemptions::ReactPayload.app_payload(current_business, ::SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE) },
            title: "Security · Secret Scanning Alert Dismissal Requests · #{current_business.name}",
            page_data: {
              sidebar: :code_security,
              selected_link: :business_security_center_dismissal_requests_secret_scanning,
            },
            layout: "layouts/react_business",
            disable_ssr: true,
          )
        end

        sig { void }
        def dismissal_request_approvers # rubocop:todo GitHub/UseRestfulActions
          approvers = can_view_request_list? ? RulesEngine::Suggestions.bypass_requests_approvers_for(current_business, ::SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE) : []
          render json: helpers.filter_suggestions(approvers)
        end

        sig { void }
        def dismissal_request_requesters # rubocop:todo GitHub/UseRestfulActions
          requesters = can_view_request_list? ? RulesEngine::Suggestions.bypass_requests_requesters_for(current_business, ::SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE) : []
          render json: helpers.filter_suggestions(requesters)
        end

        private

        sig { override.returns(T.nilable(Symbol)) }
        def authorized_orgs_actions
          nil
        end

        sig { void }
        def check_secret_scanning_enabled
          token_scanning = ::SecretScanning::Features::Business::TokenScanning.new(this_business)
          render_404 unless token_scanning.feature_available?
        end

        sig { returns(T::Boolean) }
        def can_view_request_list?
          ::SecretScanning::Features::Business::DelegatedClosures.new(this_business).can_view_request_list?(current_user)
        end
      end
    end
  end
end
