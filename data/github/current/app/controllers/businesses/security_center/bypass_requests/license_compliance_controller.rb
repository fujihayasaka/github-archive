# typed: strict
# frozen_string_literal: true

module Businesses
  module SecurityCenter
    module BypassRequests
      class LicenseComplianceController < AbstractSecurityCenterController
        skip_before_action :cap_pagination, unless: :robot?

        before_action :ensure_can_manage_enterprise_license_policy
        before_action :security_center_required

        include Repos::RulesHelper

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
        only: [:index]

        depends_on_clusters ApplicationRecord::SecurityOverviewAnalytics,
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
            sort: nil,
          }

          if can_view_request_list?
            payload = rules_bypass_requests_payload(
              viewing_source: current_business,
              filter: filter,
              page: params[:page].to_i,
              base_exemption_url: nil,
              request_types: [DependencyGraph::LicenseComplianceDelegatedClosures::CLOSURE_EXEMPTION_REQUEST_TYPE],
              repo_exemptions_base_url_suffix: "security/license-compliance/",
              required_repo_permission: nil
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
            app_payload_generator: -> { Exemptions::ReactPayload.app_payload(current_business, DependencyGraph::LicenseComplianceDelegatedClosures::CLOSURE_EXEMPTION_REQUEST_TYPE) },
            title: "Security · License Compliance Alert Requests · #{current_business.name}",
            page_data: {
              sidebar: :code_security,
              selected_link: :business_security_center_bypass_requests_license_compliance,
            },
            layout: "layouts/react_business",
            disable_ssr: true,
          )
        end

        private

        sig { override.returns(T.nilable(Symbol)) }
        def authorized_orgs_actions
          nil
        end

        sig { void }
        def ensure_can_manage_enterprise_license_policy
          render_404 unless ::Permissions::LicensePolicy.can_manage_enterprise_license_policy?(current_user, this_business)
        end

        sig { returns(T::Boolean) }
        def can_view_request_list?
          ::Permissions::LicensePolicy.can_manage_enterprise_license_policy?(current_user, this_business)
        end
      end
    end
  end
end
