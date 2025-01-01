# typed: false # rubocop:todo Sorbet/TrueSigil
# frozen_string_literal: true

module GitHub
  module RouteHelpers
    # IntegrationInstallationRequestsController#destroy
    # - DELETE /apps/:integration_id/requests/:request_id
    # - DELETE /apps/businesses/:slug/:integration_id/requests/:request_id
    # - DELETE /apps/:owner/:integration_id/requests/:request_id
    def gh_cancel_app_integration_installation_request_url(request, user)
      app = request.integration

      unless GitHub.flipper[:owner_scoped_github_apps].enabled?(user)
        return cancel_alias_app_integration_installation_request_url(app, request)
      end

      owner = app.owner

      if owner.is_a?(Business)
        cancel_business_app_integration_installation_request_url(owner, app, request)
      elsif app.synchronized_dotcom_app?
        cancel_external_app_integration_installation_request_url(owner, app, request)
      else
        cancel_user_app_integration_installation_request_url(owner, app, request)
      end
    end

    # IntegrationInstallationsController#new
    # - GET /apps/:integration_id/installations/new
    # - GET /apps/businesses/:slug/:integration_id/installations/new
    # - GET /apps/:owner/:integration_id/installations/new
    def gh_new_app_installation_path(app, user = nil)
      unless GitHub.flipper[:owner_scoped_github_apps].enabled?(user)
        return new_alias_app_installation_path(app)
      end

      owner = app.owner
      if owner.is_a?(Business)
        new_business_app_installation_path(owner, app)
      elsif app.synchronized_dotcom_app?
        new_external_app_installation_path(app)
      else
        new_user_app_installation_path(owner, app)
      end
    end

    def gh_new_app_installation_url(app, user = nil)
      unless GitHub.flipper[:owner_scoped_github_apps].enabled?(user)
        return new_alias_app_installation_url(app)
      end

      owner = app.owner
      if owner.is_a?(Business)
        new_business_app_installation_url(owner, app)
      elsif app.synchronized_dotcom_app?
        new_external_app_installation_url(app)
      else
        new_user_app_installation_url(owner, app)
      end
    end

    # IntegrationInstallationsController#select_target
    # - GET /apps/:integration_id/installations/select_target
    # - GET /apps/businesses/:slug/:integration_id/installations/select_target
    # - GET /apps/:owner/:integration_id/installations/select_target
    # - GET /third-party-apps/:integration_id/installations/select_target
    def gh_app_select_target_path(app, **params)
      unless GitHub.flipper[:owner_scoped_github_apps].enabled?(app.owner)
        return alias_app_select_target_path(app, **params)
      end

      owner = app.owner

      if owner.is_a?(Business)
        business_app_select_target_path(owner, app, **params)
      elsif app.synchronized_dotcom_app?
        external_app_select_target_path(app, **params)
      else
        user_app_select_target_path(owner, app, **params)
      end
    end

    def gh_app_select_target_url(app, **params)
      unless GitHub.flipper[:owner_scoped_github_apps].enabled?(app.owner)
        return alias_app_select_target_url(app, **params)
      end

      owner = app.owner

      if owner.is_a?(Business)
        business_app_select_target_url(owner, app, **params)
      elsif app.synchronized_dotcom_app?
        external_app_select_target_url(app, **params)
      else
        user_app_select_target_url(owner, app, **params)
      end
    end

    # IntegrationInstallationsController#permissions
    # - GET  /apps/:integration_id/installations/new/permissions
    # - GET  /apps/businesses/:slug/:integration_id/installations/new/permissions
    # - GET  /apps/:owner/:integration_id/installations/new/permissions
    #
    # - POST /apps/:integration_id/installations/new/permissions
    # - POST /apps/businesses/:slug/:integration_id/installations/new/permissions
    # - POST /apps/:owner/:integration_id/installations/new/permissions
    def gh_app_installation_permissions_path(app, user, **params)
      unless GitHub.flipper[:owner_scoped_github_apps].enabled?(user)
        return alias_app_installation_permissions_path(app, params)
      end

      owner = app.owner
      if owner.is_a?(Business)
        business_app_installation_permissions_path(owner, app, params)
      elsif app.synchronized_dotcom_app?
        external_app_installation_permissions_path(app, params)
      else
        user_app_installation_permissions_path(owner, app, params)
      end
    end

    def gh_app_installation_permissions_url(app, user, **params)
      unless GitHub.flipper[:owner_scoped_github_apps].enabled?(user)
        return alias_app_installation_permissions_url(app, params)
      end

      owner = app.owner
      if owner.is_a?(Business)
        business_app_installation_permissions_url(owner, app, params)
      elsif app.synchronized_dotcom_app?
        external_app_installation_permissions_url(app, params)
      else
        user_app_installation_permissions_url(owner, app, params)
      end
    end

    def gh_graphql_app_installation_permissions_path(**options)
      app          = options[:app]
      user         = options[:user]
      owner        = options[:owner]
      query_params = options[:query_params]

      unless GitHub.flipper[:owner_scoped_github_apps].enabled?(user)
        return alias_app_installation_permissions_path(app, query_params)
      end

      if options[:owner_type] == "Business"
        business_app_installation_permissions_path(owner, app, query_params)
      elsif options[:external_app]
        external_app_installation_permissions_path(app, query_params)
      else
        user_app_installation_permissions_path(owner, app, query_params)
      end
    end

    # IntegrationInstallationsController#create
    # - POST /apps/:integration_id/installations
    # - POST /apps/businesses/:slug/:integration_id/installations
    # - POST /apps/:owner/:integration_id/installations
    def gh_app_installations_path(app, user = nil)
      unless GitHub.flipper[:owner_scoped_github_apps].enabled?(user)
        return alias_app_installations_path(app)
      end

      owner = app.owner

      case owner
      when Business
        business_app_installations_path(owner, app)
      else
        if app.synchronized_dotcom_app?
          external_app_installations_path(app)
        else
          user_app_installations_path(owner, app)
        end
      end
    end

    # IntegrationInstallationsController#suggestions
    # - GET /apps/:integration_id/installations/suggestions
    # - GET /apps/businesses/:slug/:integration_id/installations/suggestions
    # - GET /apps/:owner/:integration_id/installations/suggestions
    def gh_app_installations_suggestions_path(app, user, **params)
      unless GitHub.flipper[:owner_scoped_github_apps].enabled?(user)
        return alias_app_installations_suggestions_path(app, params)
      end

      owner = app.owner
      if owner.is_a?(Business)
        business_app_installations_suggestions_path(owner, app, params)
      elsif app.synchronized_dotcom_app?
        external_app_installations_suggestions_path(app, params)
      else
        user_app_installations_suggestions_path(owner, app, params)
      end
    end

    # IntegrationInstallationsController#edit
    # - GET /apps/:integration_id/installations/:id
    # - GET /apps/businesses/:slug/:integration_id/installations/:id
    # - GET /apps/:owner/:integration_id/installations/:id
    def gh_edit_app_installation_path(app, installation, user, **params)
      unless GitHub.flipper[:owner_scoped_github_apps].enabled?(user)
        return edit_alias_app_installation_path(app, installation, params)
      end

      owner = app.owner
      if owner.is_a?(Business)
        edit_business_app_installation_path(owner, app, installation, params)
      elsif app.synchronized_dotcom_app?
        edit_external_app_installation_path(app, installation, params)
      else
        edit_user_app_installation_path(owner, app, installation, params)
      end
    end

    # IntegrationInstallationsController#update
    # - PUT /apps/:integration_id/installations/:id
    # - PUT /apps/businesses/:slug/:integration_id/installations/:id
    # - PUT /apps/:owner/:integration_id/installations/:id
    def gh_update_app_installation_path(app, installation, user = nil)
      unless GitHub.flipper[:owner_scoped_github_apps].enabled?(user)
        return update_alias_app_installation_path(app, installation)
      end

      owner = app.owner
      if owner.is_a?(Business)
        update_business_app_installation_path(owner, app, installation)
      elsif app.synchronized_dotcom_app?
        update_external_app_installation_path(app, installation)
      else
        update_user_app_installation_path(owner, app, installation)
      end
    end

    # IntegrationInstallationsController#edit_permissions
    # - GET /apps/:integration_id/installations/:id/permissions
    # - GET /apps/businesses/:slug/:integration_id/installations/:id/permissions
    # - GET /apps/:owner/:integration_id/installations/:id/permissions
    def gh_edit_app_installation_permissions_path(app, installation, user)
      unless GitHub.flipper[:owner_scoped_github_apps].enabled?(user)
        return edit_alias_app_installation_permissions_path(app, installation)
      end

      owner = app.owner
      if owner.is_a?(Business)
        edit_business_app_installation_permissions_path(owner, app, installation)
      elsif app.synchronized_dotcom_app?
        edit_external_app_installation_permissions_path(app, installation)
      else
        edit_user_app_installation_permissions_path(owner, app, installation)
      end
    end

    # IntegrationInstallationsController#edit_permissions
    # - PUT /apps/:integration_id/installations/:id/permissions
    # - PUT /apps/businesses/:slug/:integration_id/installations/:id/permissions
    # - PUT /apps/:owner/:integration_id/installations/:id/permissions
    def gh_update_app_installation_permissions_path(app, installation, user = nil)
      unless GitHub.flipper[:owner_scoped_github_apps].enabled?(user)
        return update_alias_app_installation_permissions_path(app, installation)
      end

      owner = app.owner
      if owner.is_a?(Business)
        update_business_app_installation_permissions_path(owner, app, installation)
      elsif app.synchronized_dotcom_app?
        update_external_app_installation_permissions_path(app, installation)
      else
        update_user_app_installation_permissions_path(owner, app, installation)
      end
    end

    # IntegrationInstallationsControllerMethods#index
    # - GET /businesses/:slug/settings/installations
    # - GET /organizations/:organizations_id/settings/installations
    # - GET /settings/installations
    def gh_settings_installations_path(target)
      case target
      when Business
        settings_business_installations_enterprise_path(target)
      when Organization
        settings_org_installations_path(target)
      when User
        settings_user_installations_path
      end
    end

    # IntegrationInstallationsControllerMethods#show
    # - GET /businesses/:slug/setings/installations/:id
    # - GET /organizations/:organization_id/setings/installations/:id
    # - GET /settings/installations/:id
    def gh_settings_installation_path(installation, params = {})
      case installation.target
      when Business
        settings_business_installation_enterprise_path(installation.target, installation, params)
      when Organization
        settings_org_installation_path(installation.target, installation, params)
      when User
        settings_user_installation_path(installation, params)
      end
    end

    # IntegrationInstallationsControllerMethods#update
    # - PUT /businesses/:slug/settings/installations/:id/update
    # - PUT /organizations/:organization_id/settings/installations/:id/update
    # - PUT /settings/installations/:id/update
    def gh_update_settings_installation_path(installation)
      case installation.target
      when Business
        update_settings_business_installation_enterprise_path(installation.target, installation)
      when Organization
        update_settings_org_installation_path(installation.target, installation)
      when User
        update_settings_user_installation_path(installation)
      end
    end

    # IntegrationInstallationsControllerMethods#permissions_update_request
    # - GET /businesses/:slug/settings/installations/:id/permissions/update
    # - GET /organizations/:organization_id/settings/installations/:id/permissions/update
    # - GET /settings/installations/:id/permissions/update
    def gh_permissions_update_request_settings_installation_path(installation)
      case installation.target
      when Business
        permissions_update_request_settings_business_installation_enterprise_path(installation.target, installation)
      when Organization
        permissions_update_request_settings_org_installation_path(installation.target, installation)
      when User
        permissions_update_request_settings_user_installation_path(installation)
      end
    end

    # IntegrationInstallationsControllerMethods#update_permissions
    # - PUT /businesses/:slug/settings/installations/:id/permissions/update
    # - PUT /organizations/:organization_id/settings/installations/:id/permissions/update
    # - PUT /settings/installations/:id/permissions/update
    def gh_update_permissions_settings_installation_path(installation)
      case installation.target
      when Business
        update_permissions_settings_business_installation_enterprise_path(installation.target, installation)
      when Organization
        update_permissions_settings_org_installation_path(installation.target, installation)
      when User
        update_permissions_settings_user_installation_path(installation)
      end
    end

    # IntegrationInstallationsControllerMethods#repositories
    # - GET /businesses/:slug/setings/installations/:id
    # - GET /organizations/:organization_id/setings/installations/:id
    # - GET /settings/installations/:id
    def gh_settings_installation_repositories_path(installation, params = {})
      case installation.target
      when Business
        "#" # TODO: Business installations can't be user-mananged today.
      when Organization
        settings_org_installation_repositories_path(installation.target, installation, params)
      when User
        settings_user_installation_repositories_path(installation, params)
      end
    end

    # IntegrationInstallationsControllerMethods#suspend
    # - POST /organizations/:organization_id/settings/installations/:id/suspended
    # - POST /enterprises/:slug/settings/installations/:id/suspended
    # - POST /settings/installations/:id/suspended
    def gh_suspend_settings_installation_path(installation)
      case installation.target
      when Business
        suspend_settings_installation_enterprise_path(installation.target, installation)
      when Organization
        suspend_settings_org_installation_path(installation.target, installation)
      else
        suspend_settings_user_installation_path(installation)
      end
    end

    # IntegrationInstallationsControllerMethods#update_contact_email
    # - DELETE /organizations/:organization_id/settings/installations/:id/suspended
    # - DELETE /enterprises/:slug/settings/installations/:id/suspended
    # - DELETE /settings/installations/:id/suspended
    def gh_unsuspend_settings_installation_path(installation)
      case installation.target
      when Business
        unsuspend_settings_installation_enterprise_path(installation.target, installation)
      when Organization
        unsuspend_settings_org_installation_path(installation.target, installation)
      else
        unsuspend_settings_user_installation_path(installation)
      end
    end

    # IntegrationTransfersControllerMethods#show
    # - GET /organizations/:organization_id/settings/apps/transfers/:id
    # - GET /enterprises/:slug/settings/apps/transfers/:id
    # - GET /settings/apps/transfers/:id
    def gh_settings_app_transfer_path(target, transfer)
      if target.organization?
        settings_org_app_transfer_path(target, transfer)
      elsif target.business?
        settings_app_transfer_enterprise_path(target, transfer)
      else
        settings_user_app_transfer_path(transfer)
      end
    end

    def gh_settings_app_transfer_url(target, transfer)
      if target.organization?
        settings_org_app_transfer_url(target, transfer)
      elsif target.business?
        settings_app_transfer_enterprise_url(target, transfer)
      else
        settings_user_app_transfer_url(transfer)
      end
    end

    # IntegrationTransfersControllerMethods#accept
    # - PUT /organizations/:organization_id/settings/apps/transfers/:id/accept
    # - PUT /enterprises/:slug/settings/apps/transfers/:id/accept
    # - PUT /settings/apps/transfers/:id/accept
    def gh_accept_settings_app_transfer_path(transfer)
      if transfer.target.organization?
        accept_settings_org_app_transfer_path(transfer.target, transfer)
      elsif transfer.target.business?
        accept_settings_app_transfer_enterprise_path(transfer.target, transfer)
      else
        accept_settings_user_app_transfer_path(transfer)
      end
    end

    # IntegrationsController#show
    # - GET /apps/:id
    # - GET /apps/businesses/:slug/:id
    # - GET /apps/:owner/:id
    def gh_app_path(app, user)
      app.public_app_path(actor: user)
    end

    def gh_settings_app_transfer_suggestions_path(integration)
      if integration.owner.organization?
        transfer_settings_org_app_suggestions_path(integration.owner, integration)
      elsif integration.owner.business?
        transfer_settings_app_suggestions_enterprise_path(integration.owner, integration)
      else
        transfer_settings_user_app_suggestions_path(integration)
      end

    end

    # Integrations::InstallationActionsController#show
    # - GET /apps/:id/installation_action
    # - GET /apps/:owner/:id/installation_action
    # - GET /apps/businesses/:slug/:id/installation_action
    def gh_app_installation_action_path(app, user = nil)
      unless GitHub.flipper[:owner_scoped_github_apps].enabled?(user)
        return alias_app_installation_action_path(app)
      end

      owner = app.owner
      if owner.is_a?(Business)
        business_app_installation_action_path(owner, app)
      elsif app.synchronized_dotcom_app?
        external_app_installation_action_path(app)
      else
        user_app_installation_action_path(owner, app)
      end
    end

    def gh_app_url(app, user = nil)
      unless GitHub.flipper[:owner_scoped_github_apps].enabled?(user)
        return alias_app_url(app)
      end

      owner = app.owner
      if owner.is_a?(Business)
        business_app_url(owner, app)
      elsif app.synchronized_dotcom_app?
        external_app_url(app)
      else
        user_app_url(owner, app)
      end
    end

    # IntegrationsControllerMethods#generate_client_secret
    # - POST /enterprises/:slug/settings/apps/:id/client_secret
    # - POST /organizations/:organization_id/settings/apps/:id/client_secret
    # - POST /settings/apps/:id/client_secret
    def gh_settings_app_create_client_secret_path(app)
      case app.owner
      when Business
        generate_client_secret_settings_app_enterprise_path(app.owner, app)
      when Organization
        generate_client_secret_settings_org_app_path(app.owner, app)
      when User
        generate_client_secret_settings_user_app_path(app)
      end
    end

    # IntegrationsControllerMethods#remove_client_secret
    # - DELETE /enterprises/:slug/settings/apps/:id/client_secret
    # - DELETE /organizations/:organization_id/settings/apps/:id/client_secret
    # - DELETE /settings/apps/:id/client_secret
    def gh_settings_app_remove_client_secret_path(app)
      case app.owner
      when Business
        -> (client_secret) { remove_client_secret_settings_app_enterprise_path(app.owner, app, client_secret) }
      when Organization
        -> (client_secret) { remove_client_secret_settings_org_app_path(app.owner, app, client_secret) }
      when User
        -> (client_secret) { remove_client_secret_settings_user_app_path(app, client_secret) }
      end
    end

    # IntegrationsControllerMethods#index
    # - GET /enterprises/:slug/settings/apps
    # - GET /organizations/:organization_id/settings/apps
    # - GET /settings/apps
    def gh_settings_apps_path(context)
      if context.business?
        settings_apps_enterprise_path(context)
      elsif context.organization?
        settings_org_apps_path(context)
      elsif context.user?
        settings_user_apps_path
      end
    end

    # IntegrationsControllerMethods#show
    # - GET /enterprises/:slug/settings/apps/:id
    # - GET /organizations/:organization_id/settings/apps/:id
    # - GET /settings/apps/:id
    def gh_settings_app_path(app)
      case app.owner
      when Business
        settings_app_enterprise_path(app.owner, app)
      when Organization
        settings_org_app_path(app.owner, app)
      when User
        settings_user_app_path(app)
      else
        "#"
      end
    end

    # IntegrationsControllerMethods#permissions
    # - GET /enterprises/:slug/settings/apps/:id/permissions
    # - GET /organizations/:organization_id/settings/apps/:id/permissions
    # - GET /settings/apps/:id/permissions
    def gh_settings_app_permissions_path(app)
      case app.owner
      when Business
        settings_app_permissions_enterprise_path(app.owner, app)
      when Organization
        settings_org_app_permissions_path(app.owner, app)
      when User
        settings_user_app_permissions_path(app)
      end
    end

    # IntegrationsControllerMethods#installations
    # - GET /enterprises/:slug/settings/apps/:id/installations
    # - GET /organizations/:organization_id/settings/apps/:id/installations
    # - GET /settings/apps/:id/installations
    def gh_settings_app_installations_path(app)
      case app.owner
      when Business
        settings_app_installations_enterprise_path(app.owner, app)
      when Organization
        settings_org_app_installations_path(app.owner, app)
      when User
        settings_user_app_installations_path(app)
      end
    end

    # IntegrationsControllerMethods#advanced
    # - GET /enterprises/:slug/settings/apps/:id/advanced
    # - GET /organizations/:organization_id/settings/apps/:id/advanced
    # - GET /settings/apps/:id/advanced
    def gh_settings_app_advanced_path(app)
      case app.owner
      when Business
        settings_app_advanced_enterprise_path(app.owner, app)
      when Organization
        settings_org_app_advanced_path(app.owner, app)
      when User
        settings_user_app_advanced_path(app)
      end
    end

    # IntegrationsControllerMethods#beta_features
    # - GET /enterprises/:slug/settings/apps/:id/beta
    # - GET /organizations/:organization_id/settings/apps/:id/beta
    # - GET /settings/apps/:id/beta
    def gh_settings_app_beta_features_path(app)
      case app.owner
      when Business
        settings_app_beta_features_enterprise_path(app.owner, app)
      when Organization
        settings_org_app_beta_features_path(app.owner, app)
      when User
        settings_user_app_beta_features_path(app)
      end
    end

    # IntegrationsControllerMethods#beta_feature_toggle
    # - GET /enterprises/:slug/settings/apps/:id/beta-toggle
    # - GET /organizations/:organization_id/settings/apps/:id/beta-toggle
    # - GET /settings/apps/:id/beta-toggle
    def gh_settings_app_beta_feature_toggle_path(app)
      case app.owner
      when Business
        settings_app_beta_feature_toggle_enterprise_path(app.owner, app)
      when Organization
        settings_org_app_beta_feature_toggle_path(app.owner, app)
      when User
        settings_user_app_beta_feature_toggle_path(app)
      end
    end

    # IntegrationsControllerMethods#new
    # - GET /businesses/:slug/settings/apps/new
    # - GET /organizations/:organization_id/settings/apps/new
    # - GET /settings/apps/new
    def gh_new_settings_app_path(context)
      if context.business?
        new_settings_app_enterprise_path(context)
      elsif context.organization?
        new_settings_org_app_path(context)
      elsif context.user?
        new_settings_user_app_path
      end
    end

    # IntegrationsControllerMethods#update_permissions
    # - PUT /enterprises/:slug/settings/apps/:id/permissions
    # - PUT /organizations/:organization_id/settings/apps/:id/permissions
    # - PUT /settings/apps/:id/permissions
    def gh_update_permissions_settings_apps_path(app)
      case app.owner
      when Business
        update_settings_app_permissions_enterprise_path(app.owner, app)
      when Organization
        update_permissions_settings_org_app_path(app.owner, app)
      when User
        update_permissions_settings_user_app_path(app)
      end
    end

    # IntegrationsControllerMethods#preview_permissions_note
    # - GET /businesses/:slug/settings/apps/:id/preview_note
    # - GET /organizations/:organization_id/settings/apps/:id/preview_note
    # - GET /settings/apps/:id/preview_note
    def gh_preview_permissions_note_apps_path(app, field:)
      if app.owner.is_a?(Business)
        preview_permissions_note_app_enterprise_path(app.owner, field: field)
      elsif app.owner.organization?
        preview_permissions_note_org_app_path(app.owner, field: field)
      else
        preview_permissions_note_user_app_path(field: field)
      end
    end

    # IntegrationsControllerMethods#generate_key
    # - POST /enterprises/:slug/settings/apps/:id/key
    # - POST /organizations/:organization_id/settings/apps/:id/key
    # - POST /settings/apps/:id/key
    def gh_generate_key_settings_app_path(app)
      case app.owner
      when Business
        generate_key_settings_app_enterprise_path(app.owner, app)
      when Organization
        generate_key_settings_org_app_path(app.owner, app)
      when User
        generate_key_settings_user_app_path(app)
      end
    end

    # IntegrationsControllerMethods#remove_key
    # - DELETE /enterprises/:slug/settings/apps/:id/key/:key_id
    # - DELETE /organizations/:organization_id/settings/apps/:id/key/:key_id
    # - DELETE /settings/apps/:id/key/:key_id
    def gh_remove_key_settings_app_path(app, key)
      case app.owner
      when Business
        remove_key_settings_app_enterprise_path(app.owner, app, key)
      when Organization
        remove_key_settings_org_app_path(app.owner, app, key)
      when User
        remove_key_settings_user_app_path(app, key)
      end
    end

    # IntegrationsControllerMethods#keys
    # - GET /enterprises/:slug/settings/apps/:id/keys
    # - GET /organizations/:organization_id/settings/apps/:id/keys
    # - GET /settings/apps/:id/keys
    def gh_list_keys_settings_app_path(app)
      case app.owner
      when Business
        list_keys_settings_app_enterprise_path(app.owner, app)
      when Organization
        list_keys_settings_org_app_path(app.owner, app)
      when User
        list_keys_settings_user_app_path(app)
      end
    end

    # IntegrationsControllerMethods#make_public
    # - PUT /organizations/:organization_id/settings/apps/:id/public
    # - PUT /settings/apps/:id/public
    def gh_make_public_settings_app_path(app)
      if app.owner.organization?
        make_public_settings_org_app_path(app.owner, app)
      elsif app.owner.user?
        make_public_settings_user_app_path(app)
      end
    end

    # IntegrationsControllerMethods#make_private
    # - PUT /organizations/:organization_id/settings/apps/:id/private
    # - PUT /settings/apps/:id/private
    def gh_make_private_settings_app_path(app)
      if app.owner.organization?
        make_private_settings_org_app_path(app.owner, app)
      elsif app.owner.user?
        make_private_settings_user_app_path(app)
      end
    end

    # IntegrationsControllerMethods#transfer
    # - PUT /organizations/:organization_id/settings/apps/:id/transfer
    # - PUT /enterprises/:slug/settings/apps/:id/transfer
    # - PUT /settings/apps/:id/public/transfer
    def gh_transfer_settings_app_path(app)
      if app.owner.organization?
        transfer_settings_org_app_path(app.owner, app)
      elsif app.owner.business?
        transfer_settings_app_enterprise_path(app.owner, app)
      else
        transfer_settings_user_app_path(app)
      end
    end

    # IntegrationsControllerMethods#revoke_all_tokens
    # - POST /enterprises/:slug/settings/apps/:id/revoke_all_tokens
    # - POST /organizations/:organization_id/settings/apps/:id/revoke_all_tokens
    # - POST /settings/apps/:id/public/revoke_all_tokens
    def gh_integration_revoke_all_tokens_path(app)
      case app.owner
      when Business
        revoke_all_tokens_settings_app_enterprise_path(app.owner, app)
      when Organization
        revoke_all_tokens_settings_org_app_path(app.owner, app)
      when User
        revoke_all_tokens_settings_user_app_path(app)
      end
    end

    # IntegrationsControllerMethods#agent
    # - GET /enterprises/:slug/settings/apps/:id/copilot
    # - GET /organizations/:organization_id/settings/apps/:id/copilot
    # - GET /settings/apps/:id/copilot
    def gh_settings_app_integration_agent_path(app)
      case app.owner
      when Business
        settings_app_copilot_enterprise_path(app.owner, app)
      when Organization
        settings_org_app_copilot_path(app.owner, app)
      when User
        settings_user_app_copilot_path(app)
      end
    end

    # IntegrationsControllerMethods#update_agent
    # - PUT /enterprises/:slug/settings/apps/:id/copilot
    # - PUT /organizations/:organization_id/settings/apps/:id/copilot
    # - PUT /settings/apps/:id/copilot
    def gh_settings_app_update_integration_agent_path(app)
      case app.owner
      when Business
        settings_app_update_copilot_enterprise_path(app.owner, app)
      when Organization
        settings_org_app_update_copilot_path(app.owner, app)
      when User
        settings_user_app_update_copilot_path(app)
      end
    end

    # IntegrationsControllerMethods#index
    # - POST /enterprises/:slug/settings/apps/:id/sign_agreement
    # - POST /organizations/:organization_id/settings/apps/:id/sign_agreement
    # - POST /settings/apps/:id/sign_agreement
    def gh_settings_apps_sign_agreement_path(app)
      case app.owner
      when Business
        settings_app_sign_agreement_enterprise_path(app.owner, app)
      when Organization
        settings_org_app_sign_agreement_path(app.owner, app)
      when User
        settings_user_app_sign_agreement_path(app)
      end
    end
  end
end
