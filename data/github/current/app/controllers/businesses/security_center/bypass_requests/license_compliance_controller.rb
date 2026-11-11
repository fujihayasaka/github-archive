# typed: true
# frozen_string_literal: true

require "osslicensecompliance-client"

class Businesses::SecurityCenter::BypassRequests::LicenseComplianceController < Businesses::BusinessController
  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries

  before_action :ensure_license_compliance_enabled
  before_action :manage_permissions_required

  sig { void }
  def index
    client = OSSLicenseCompliance::Twirp::OSSLicenseComplianceClient.new
    response = client.get_reviewable_alerts(enterprise_id: this_business.id)
    respond_with_react(
      app_name: "license-compliance-alerts",
      payload: LicenseComplianceAlertsRoutePayload.new(
        enterprise_id: this_business.id,
        enterprise_name: this_business.name,
        alerts: response.alerts.to_a,
        current_user: current_user,
      ),
      title: "License Policy · #{this_business.name}",
      layout: "react_business",
      page_data: {
        sidebar: :code_security,
        selected_link: :business_security_center_bypass_requests_license_compliance,
      }
    )
  end

  private

  sig { void }
  def ensure_license_compliance_enabled
    render_404 unless FeatureFlag.vexi.enabled?(:dependency_graph_license_compliance, this_business, default: false)
  end

  class LicenseComplianceAlertsRoutePayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "licenseComplianceAlertsRoute"
    end

    sig { params(enterprise_id: Integer, enterprise_name: String, alerts: T::Array[OSSLicenseCompliance::V0::Alert], current_user: User).void }
    def initialize(enterprise_id:, enterprise_name:, alerts:, current_user:)
      @enterprise_id = enterprise_id
      @enterprise_name = enterprise_name
      @alerts = alerts
      @current_user = current_user
    end

    sig { params(status: T.any(Symbol, Integer)).returns(String) }
    def format_status(status)
      case status
      when :ALERT_STATUS_CLOSED, 3  # ALERT_STATUS_CLOSED = 3
        "Dismissed"
      else
        "Open"
      end
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload
      response = {
        enterpriseId: @enterprise_id,
        enterpriseName: @enterprise_name,
        alerts: [],
      }
      @alerts.each do |alert|
        repo = Repository.find_by(id: alert.repository_id)
        link = nil
        if repo.present? && repo.readable_by?(@current_user)
          link = UrlHelpers.repository_license_compliance_scanning_alert_url(
            host: GitHub.url,
            user_id: repo.owner_display_login,
            repository: repo,
            number: alert.number,
          )
        end

        response[:alerts] << {
          number: alert.number,
          status: format_status(alert.status),
          createdAt: alert.created_at&.to_time&.strftime("%b %d"),
          manifestName: alert.manifest_name,
          packageEcosystem: DependencyReviewHelper::ECOSYSTEM_MAPPINGS[alert.package_ecosystem] || alert.package_ecosystem.to_s.downcase,
          packageName: alert.package_name,
          packageVersion: alert.package_version,
          license: alert.license,
          link: link,
        }
      end
      response
    end
  end

  sig { void }
  def manage_permissions_required
    render_404 unless Permissions::LicensePolicy.can_manage_enterprise_license_policy?(current_user, this_business)
  end
end
