# typed: true
# frozen_string_literal: true

module Businesses
  module TeamSync
    class OktaCredentialsController < ::Businesses::BusinessController

      before_action :require_okta_identity_provider
      before_action :business_owner_required
      before_action :require_team_sync_tenant, only: [:edit, :update]

      after_action :replicate_changes_to_orgs, only: [:update]

      javascript_bundle :"team-sync"

      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::Configurations,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Notify,
        ApplicationRecord::Collab,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Mysql5,
        ApplicationRecord::Repositories,
        ApplicationRecord::Copilot,
        ApplicationRecord::Billing,
        only: [:edit]

      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::Configurations,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Notify,
        ApplicationRecord::Collab,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Mysql5,
        ApplicationRecord::Repositories,
        ApplicationRecord::Copilot,
        ApplicationRecord::Billing,
        only: [:new]

      def new
        okta_credentials = ::TeamSync::OktaCredentials.new

        if this_business.team_sync_tenant.present?
          render "businesses/team_sync/okta_credentials/edit", locals: { business: this_business, okta_credentials: okta_credentials }
          return
        end

        render "businesses/team_sync/okta_credentials/new", locals: { business: this_business, okta_credentials: okta_credentials }
      end

      def create
        okta_credentials = ::TeamSync::OktaCredentials.new(get_okta_credentials_params)
        if !okta_credentials.valid?
          flash.now[:error] = "There were errors with your credentials."
          render "businesses/team_sync/okta_credentials/new", locals: { business: this_business, okta_credentials: okta_credentials }
          return
        end

        err = team_sync_setup_flow.initiate_setup(provider_type: provider.type, provider_id: provider.id, encrypted_ssws_token: okta_credentials.ssws_token, url: okta_credentials.url)
        if err
          flash.now[:error] = Orgs::TeamSyncController::ERROR_MESSAGES[err] % { err: err, provider_type: provider.type }
          render "businesses/team_sync/okta_credentials/new", locals: { business: this_business, okta_credentials: okta_credentials }
          return
        end

        team_sync_setup_flow.tenant.update(status: "ready")

        error_key, twirp_error = team_sync_setup_flow.approve
        if error_key
          team_sync_setup_flow.tenant.disable

          flash.now[:error] = Orgs::TeamSyncController::ERROR_MESSAGES[error_key] % { err: twirp_error.msg }
          render "businesses/team_sync/okta_credentials/new", locals: { business: this_business, okta_credentials: okta_credentials }
          return
        end

        flash[:notice] = "Team synchronization setup has been enabled"
        redirect_to settings_security_enterprise_url(this_business)
      end

      def edit
        okta_credentials = ::TeamSync::OktaCredentials.new(url: @tenant.url, ssws_token: "")

        render "businesses/team_sync/okta_credentials/edit", locals: { business: this_business, okta_credentials: okta_credentials }
      end

      def update
        okta_credentials_params = get_okta_credentials_params
        okta_credentials_from_request = ::TeamSync::OktaCredentials.new(okta_credentials_params)
        okta_credentials_with_ssws_token = okta_credentials_from_request
        # ssws_token is an optional parameter, if it is not provided, we create a new OktaCredentials object with the token loaded from the db
        if !okta_credentials_params.key?(:ssws_token)
          okta_credentials_params[:ssws_token] = @tenant.encrypted_ssws_token
          okta_credentials_with_ssws_token = ::TeamSync::OktaCredentials.new(okta_credentials_params)
        end

        if !okta_credentials_with_ssws_token.valid?
          # generate errors on the request object
          okta_credentials_from_request.valid?
          flash.now[:error] = "There were errors with your credentials."
          render "businesses/team_sync/okta_credentials/edit", locals: { business: this_business, okta_credentials: okta_credentials_from_request }
          return
        end

        newly_enabled = @tenant.status != "enabled"

        if @tenant.update(provider_type: provider.type, provider_id: provider.id, encrypted_ssws_token: okta_credentials_with_ssws_token.ssws_token, url: okta_credentials_with_ssws_token.url, status: "enabled")
          err = @tenant.register

          if err
            flash.now[:error] = Orgs::TeamSyncController::ERROR_MESSAGES[err] % { err: err, provider_type: provider.type }
            render "businesses/team_sync/okta_credentials/edit", locals: { business: this_business, okta_credentials: okta_credentials_from_request }
            return
          end

          if newly_enabled
            team_sync_setup_flow.instrument "enabled"
          end
        else
          flash.now[:error] = "There were errors with your credentials."
          render "businesses/team_sync/okta_credentials/edit", locals: { business: this_business, okta_credentials: okta_credentials_from_request }
          return
        end

        flash[:notice] = "Team synchronization credentials have been updated"
        redirect_to settings_security_enterprise_path(this_business)
      end

      private

      def get_okta_credentials_params
        params.require(:team_sync_okta_credentials).permit(:ssws_token, :url)
      end

      def require_team_sync_tenant
        @tenant = this_business.team_sync_tenant
        if @tenant.nil?
          flash.now[:error] = "The tenant for this enterprise account does not exist."
          render "businesses/team_sync/okta_credentials/new", locals: { business: this_business, okta_credentials: ::TeamSync::OktaCredentials.new }
          return
        end
        @tenant
      end

      memoize def provider
        ::TeamSync::Provider.detect(issuer: this_business.external_identity_session_owner.saml_provider&.issuer)
      end

      def require_okta_identity_provider
        unless provider&.okta?
          flash[:error] = Orgs::TeamSyncController::ERROR_MESSAGES[:invalid_provider_type]
          redirect_to settings_security_enterprise_url(this_business)
        end
      end

      memoize def team_sync_setup_flow
        ::TeamSync::SetupFlow.new(business: this_business, actor: current_user)
      end

      def replicate_changes_to_orgs
        this_business.organizations.each do |org|
          UpdateTeamSyncForBusinessOrganizationJob.perform_later(org_id: org.id)
        end
      end
    end
  end
end
