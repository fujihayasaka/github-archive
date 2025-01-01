# typed: strict
# frozen_string_literal: true

module Orgs
  module SecurityCenter
    class SecretRiskAssessmentRepositoriesController < Orgs::Controller
      depends_on_clusters \
        ApplicationRecord::Collab,
        ApplicationRecord::Configurations,
        ApplicationRecord::Iam,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Mysql1,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Repositories,
        ApplicationRecord::SecurityOverviewAnalytics

      layout false

      before_action :login_required
      before_action :assessment_access_required

      sig { void }
      def index
        render json: {
          items: query.picker_repos,
          totalCount: query.count,
        }
      end

      private

      sig { returns(::SecretScanning::BulkEnablementQuery) }
      memoize def query
        ::SecretScanning::BulkEnablementQuery.new(
          org: this_organization,
          actor: current_user,
          cap_filter:,
          remote_ip:,
          search_query: params[:q],
          user_session:,
          assessment_number: params[:assessment_id].to_i,
        )
      end

      sig { void }
      def assessment_access_required
        return render_404 unless this_organization

        access_control = ::SecretScanning::AccessControl::SecretRiskAssessments.new(this_organization)
        render_404 unless access_control.has_access_to_secret_risk_assessments?(current_user)
      end
    end
  end
end
