# typed: true
# frozen_string_literal: true

module Orgs
  module TeamSync
    class OktaCredentialsController < ::Orgs::Controller

      before_action :require_okta_identity_provider
      before_action :organization_admin_required
      before_action :require_team_sync_tenant, only: [:edit, :update]

      javascript_bundle :"team-sync"

      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::Configurations,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Collab,
        ApplicationRecord::Notify,
        ApplicationRecord::Repositories,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Billing,
        ApplicationRecord::Mysql5,
        only: [:edit]

      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::Configurations,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Collab,
        ApplicationRecord::Notify,
        ApplicationRecord::Repositories,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Billing,
        ApplicationRecord::Mysql5,
        only: [:new]

      depends_on_clusters ApplicationRecord::Copilot,
        only: [:new, :edit], optional: true

      def new
        okta_credentials = ::TeamSync::OktaCredentials.new

        if this_organization.team_sync_tenant.present?
          render "orgs/team_sync/okta_credentials/edit", locals: { organization: this_organization, okta_credentials: okta_credentials }
          return
        end

        render "orgs/team_sync/okta_credentials/new", locals: { organization: this_organization, okta_credentials: okta_credentials }
      end

      def create
        okta_credentials = ::TeamSync::OktaCredentials.new(get_okta_credentials_params)
        if !okta_credentials.valid?
          flash.now[:error] = "There were errors with your credentials."
          render "orgs/team_sync/okta_credentials/new", locals: { organization: this_organization, okta_credentials: okta_credentials }
          return
        end

        err = team_sync_setup_flow.initiate_setup(provider_type: provider.type, provider_id: provider.id, encrypted_ssws_token: okta_credentials.ssws_token, url: okta_credentials.url)
        if err
          flash[:error] = Orgs::TeamSyncController::ERROR_MESSAGES[err] % { err: err, provider_type: provider.type }
          render "orgs/team_sync/okta_credentials/new", locals: { organization: this_organization, okta_credentials: okta_credentials }
          return
        end

        team_sync_setup_flow.tenant.update(status: "ready")

        error_key, twirp_error = team_sync_setup_flow.approve
        if error_key
          team_sync_setup_flow.tenant.disable

          flash.now[:error] = Orgs::TeamSyncController::ERROR_MESSAGES[error_key] % { err: twirp_error.msg }
          render "orgs/team_sync/okta_credentials/new", locals: { organization: this_organization, okta_credentials: okta_credentials }
          return
        end

        flash[:notice] = "Team synchronization setup has been enabled"
        redirect_to settings_org_security_url(this_organization)
      end

      def edit
        okta_credentials = ::TeamSync::OktaCredentials.new(url: @tenant.url, ssws_token: "")

        render "orgs/team_sync/okta_credentials/edit", locals: { organization: this_organization, okta_credentials: okta_credentials }
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
          render "orgs/team_sync/okta_credentials/edit", locals: { organization: this_organization, okta_credentials: okta_credentials_from_request }
          return
        end

        if @tenant.update(provider_type: provider.type, provider_id: provider.id, encrypted_ssws_token: okta_credentials_with_ssws_token.ssws_token, url: okta_credentials_with_ssws_token.url, status: "enabled")
          err = @tenant.register

          if err
            flash.now[:error] = Orgs::TeamSyncController::ERROR_MESSAGES[err] % { err: err, provider_type: provider.type }
            render "orgs/team_sync/okta_credentials/edit", locals: { organization: this_organization, okta_credentials: okta_credentials_from_request }
            return
          end
        else
          flash.now[:error] = "There were errors with your credentials."
          render "orgs/team_sync/okta_credentials/edit", locals: { organization: this_organization, okta_credentials: okta_credentials_from_request }
          return
        end

        flash[:notice] = "Team synchronization credentials have been updated"
        redirect_to settings_org_security_url(this_organization)
      end

      private

      def get_okta_credentials_params
        params.require(:team_sync_okta_credentials).permit(:ssws_token, :url)
      end

      memoize def provider
        ::TeamSync::Provider.detect(issuer: this_organization.external_identity_session_owner.saml_provider.issuer)
      end

      def require_okta_identity_provider
        unless provider&.okta?
          flash[:error] = Orgs::TeamSyncController::ERROR_MESSAGES[:invalid_provider_type]
          redirect_to settings_org_security_url(this_organization)
        end
      end

      def require_team_sync_tenant
        @tenant = this_organization.team_sync_tenant
        if @tenant.nil?
          flash[:error] = "The tenant for this organization does not exist."
          render "orgs/team_sync/okta_credentials/new", locals: { organization: this_organization, okta_credentials: ::TeamSync::OktaCredentials.new }
          return
        end
        @tenant
      end

      memoize def team_sync_setup_flow
        ::TeamSync::SetupFlow.new(organization: this_organization, actor: current_user)
      end
    end
  end
end
