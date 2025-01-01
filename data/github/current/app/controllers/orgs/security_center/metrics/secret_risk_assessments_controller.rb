# typed: strict
# frozen_string_literal: true

module Orgs
  module SecurityCenter
    module Metrics
      class SecretRiskAssessmentsController < AbstractSecurityCenterController
        include ApplicationController::VerifiedFetchDependency

        after_action :ensure_security_overview_analytics_reconciliation, only: [:index]
        after_action :trigger_security_overview_analytics_backfill, only: [:index]

        before_action :require_feature_flag
        before_action :check_secret_risk_assessments_permission

        allow_verified_fetch except: [:index]

        sig { returns(String) }
        def self.react_bundle_name
          "secret-risk-assessment"
        end

        # TODO: Restrict access to right users/orgs
        sig { void }
        def index
          data = log_timing(step: "build locals") do
            {
              backfill_in_progress: ::SecurityCenter::SecurityFeatures.security_center_available?(this_organization) ? this_organization.trigger_security_center_reconciliation : false,
              selected_tab: :secret_risk_assessment,
            }
          end

          # TODO: Implement getting assessment from TSS
          assessment = ::SecretScanning::Models::RiskAssessment::Assessment.new(
            can_request_another_assessment: true,
            next_request_available_at: DateTime.now + 2.days,
            last_status_change: DateTime.now - 1.day,
            is_complete: params[:complete].present?,
            total_scans_wanted: 100,
            total_scans_completed: rand(100),
            total_tokens_found: rand(100),
            total_tokens_found_in_public_repo: rand(100),
            total_tokens_found_push_protected_patterns: rand(100),
            total_tokens_found_non_provider_patterns: rand(100),
            tokens: [
              ::SecretScanning::Models::RiskAssessment::Assessment::TokenTypeResult.new(
                name: "Clojar",
                unique_tokens_found_count: 12,
              ),
              *100.times.map do
                uuid = Random.uuid
                ::SecretScanning::Models::RiskAssessment::Assessment::TokenTypeResult.new(
                  name: uuid,
                  unique_tokens_found_count: rand(1..200),
                )
              end,
            ].sort_by(&:unique_tokens_found_count).reverse,
          ) unless params[:landing]

          render_react_app(
            title: "Security · Secret Risk Assessment · #{this_organization.display_login}",
            payload: {
              org: {
                login: this_organization.display_login,
              },
              assessment: assessment&.serialize,
              help_url: GitHub.help_url,
            },
            # TODO: Adjust sidebar to account for Teams plan, unbundled Secret Scanning, and full Security Center
            layout: "layouts/security_center/with_sidebar",
            page_data: { data: },
          )
        end

        # TODO: Implement creating an assessment
        sig { void }
        def create
          sleep(2)
          render json: nil, status: 200
        end

        private

        sig { void }
        def require_feature_flag
          render_404 unless ::SecretScanning::Features::Org::TokenScanning.new(this_organization).secret_risk_assessment_available?
        end

        sig { void }
        def check_secret_risk_assessments_permission
          return render_404 unless this_organization
          return render_404 unless current_user
          render_404 unless ::SecretScanning::AccessControl::SecretRiskAssessments.new(this_organization).has_access_to_secret_risk_assessments?(current_user)
        end

        depends_on_clusters(
          ApplicationRecord::Mysql1,
          ApplicationRecord::Mysql2,
          ApplicationRecord::Configurations,
          ApplicationRecord::Iam,
          ApplicationRecord::IamAbilities,
          ApplicationRecord::Repositories,
          ApplicationRecord::Notify,
          ApplicationRecord::NotificationsEntries,
          ApplicationRecord::Collab,
          ApplicationRecord::SecurityOverviewAnalytics,
          only: [:index],
        )
      end
    end
  end
end
