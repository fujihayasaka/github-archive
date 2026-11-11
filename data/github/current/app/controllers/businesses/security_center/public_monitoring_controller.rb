# typed: strict
# frozen_string_literal: true

module Businesses
  module SecurityCenter
    class PublicMonitoringController < AbstractSecurityCenterController
      include SecretScanningControllerHelper
      include ApplicationController::VerifiedFetchDependency

      before_action :check_public_monitoring_enabled
      before_action :check_public_monitoring_authorized

      allow_verified_fetch

      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::Repositories,
        ApplicationRecord::Billing,
        ApplicationRecord::Configurations,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Collab,
        ApplicationRecord::Copilot,
        ApplicationRecord::Ballast,
        only: [:index, :show]

      sig { returns(String) }
      def self.react_bundle_name
        "secret-scanning-public-monitoring"
      end

      sig { void }
      def index
        title = "Security · Public Monitoring · #{current_business.name}"
        pubmon = ::SecretScanning::Features::Business::PublicMonitoring.new(this_business)

        unless pubmon.enabled?
          respond_with_react(
            payload: IndexPayload.new(
              ::SecretScanning::PublicMonitoringAlertListResponse.empty.serialize_ui.merge(
                selfServiceEligible: true,
                verifiedDomains: [],
              ),
            ),
            title: title,
            page_data: {
              sidebar: :code_security,
              selected_link: :business_security_center_public_monitoring,
            },
            layout: "react_business",
          )
          return
        end

        cursor, valid = cursor_from_params

        return render_404 if !valid && params[:cursor].present?

        response = ::SecretScanning::PublicMonitoringQueryService.list_alerts(
          business: this_business,
          current_user: current_user,
          cursor: cursor,
          per_page: PAGE_SIZE,
        )

        return render_404 if response.cursor_not_found?

        verified_domains = ::SecretScanning::PublicMonitoringQueryService.verified_domains_for(business: this_business)
        payload_data = response.serialize_ui.merge(verifiedDomains: verified_domains)

        respond_with_react(
          payload: IndexPayload.new(payload_data),
          title: title,
          page_data: {
            sidebar: :code_security,
            selected_link: :business_security_center_public_monitoring,
          },
          layout: "react_business",
        )
      end

      sig { void }
      def show
        alert_key = params[:id]
        return render_404 if alert_key.blank?

        begin
          alert_data = ::SecretScanning::Encryption::PublicMonitoringAlertKey.decrypt(alert_key)
        rescue ArgumentError, JSON::ParserError, KeyError, TypeError, OpenSSL::Cipher::CipherError
          return render_404
        end

        repository_id = alert_data[:repository_id]
        alert_number = alert_data[:alert_number]
        business_id = alert_data[:business_id]
        current_page = params[:page].present? ? params[:page].to_i : 1

        return render_404 unless repository_id.present? && alert_number.present?

        # Reject keys that were minted for a different enterprise. An attacker
        # who obtains an encrypted alert key from another enterprise's public
        # monitoring view (e.g. via a leaked URL) must not be able to use it
        # to render alert details inside their own enterprise.
        return render_404 unless business_id == this_business.id

        repository = Repository.active.find_by(id: repository_id)
        # Hide alert details when the repository no longer exists or is no
        # longer public.  Public monitoring only surfaces leaks in public repos;
        # once a repo is deleted or made private the alert should not be viewable.
        return render_404 unless repository&.public?

        alerts_service = ::SecretScanning::Services::AlertsService.new
        result, service_error = alerts_service.get_alert(repository, current_user, alert_number, page: current_page)

        if service_error.present?
          raise service_error
        end

        return render_404 unless result

        render json: serialize_show_ui(result, repository, current_page)
      end

      private

      # Required abstract method from AbstractSecurityCenterController.
      # Returns nil because pubmon alerts are for leaks in external public repos (outside the
      # enterprise's orgs), so org-level permission scoping does not apply.
      # Access is controlled at the enterprise level by check_public_monitoring_authorized.
      sig { override.returns(T.nilable(Symbol)) }
      def authorized_orgs_actions
        nil
      end

      sig { void }
      def check_public_monitoring_enabled
        pubmon = ::SecretScanning::Features::Business::PublicMonitoring.new(this_business)
        if action_name == "index"
          render_404 unless pubmon.enabled? || pubmon.settings_available?
        else
          render_404 unless pubmon.enabled?
        end
      end

      sig { void }
      def check_public_monitoring_authorized
        render_404 unless ::SecretScanning::AccessControl::PublicMonitoring.can_access?(this_business, current_user)
      end

      PAGE_SIZE = 25

      sig { params(result: GitHub::TokenScanning::Service::Token, repository: Repository, current_page: Integer).returns(T::Hash[Symbol, T.untyped]) }
      def serialize_show_ui(result, repository, current_page)
        loc_service = ::SecretScanning::Services::LocationSerializationService

        locations = result.included_locations.map do |location|
          loc_service.serialize_location_for_ui(location, repository)
        end

        first_location = locations.first

        {
          locations: locations,
          totalLocationsCount: result.included_locations_count,
          locationsPerPage: ::SecretScanning::Services::AlertsService::LOCATIONS_PER_PAGE,
          page: current_page,
          repositoryOwner: repository.owner_display_login,
          repositoryName: repository.name,
          commitAuthorEmail: first_location&.dig(:commitAuthorEmail),
          committedAt: first_location&.dig(:commitCreatedAt),
        }
      end

      class IndexPayload < ReactPayload::Base
        sig { override.returns(String) }
        def route_id
          "businessPublicMonitoringRoute"
        end

        sig { params(payload: T::Hash[Symbol, T.untyped]).void }
        def initialize(payload)
          @payload = payload
        end

        sig { override.returns(T::Hash[Symbol, T.untyped]) }
        def payload
          @payload
        end
      end
    end
  end
end
