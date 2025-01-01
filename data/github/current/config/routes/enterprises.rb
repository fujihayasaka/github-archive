# typed: true
# frozen_string_literal: true

T.bind(self, ActionDispatch::Routing::Mapper)

# Redirect the legacy enterprise account profile path
get "/businesses/:slug", to: redirect("/enterprises/%{slug}")

get "enterprises/oauth_callback", to: "businesses/azure_auth_callback#callback"
get "enterprises/azure_callback", to: "businesses/virtual_network_settings#new"

get "/account/enterprises/new",
  to: "businesses/trial_accounts#new",
  as: :enterprise_trial_accounts_new
get "/account/enterprises/new/:organization_id",
  to: "businesses/trial_accounts#new",
  as: :enterprise_trial_accounts_new_organization
post "/account/enterprises/create",
  to: "businesses/trial_accounts#create",
  as: :enterprise_trial_accounts_create
post "/account/enterprises/check_enterprise_slug",
  to: "businesses/trial_accounts#check_slug",
  as: :enterprise_trial_accounts_check_slug
post "/enterprises/check_slug",
  to: "businesses/slug#check_slug",
  as: :enterprise_check_slug
get "enterprises/creation_from_coupon",
  to: "businesses/creation_from_coupon#new",
  as: :new_enterprise_from_coupon
post "enterprises/creation_from_coupon",
to: "businesses/creation_from_coupon#create",
  as: :create_enterprise_from_coupon
delete "enterprises/creation_from_coupon",
to: "businesses/creation_from_coupon#destroy",
  as: :delete_enterprise_from_coupon
post "/enterprises/creation_from_coupon/check_slug",
to: "businesses/creation_from_coupon#check_slug",
  as: :create_enterprise_from_coupon_check_slug
post "/account/enterprises/check_billing_email",
  to: "businesses/trial_accounts#check_billing_email",
  as: :enterprise_trial_accounts_check_billing_email
post "/account/enterprises/check_shortcode",
  to: "businesses/trial_accounts#check_shortcode",
  as: :enterprise_trial_accounts_check_shortcode
get "/account/enterprises/data_residency_provisioning/:subdomain",
  to: "businesses/multi_tenant_provisioning_requests#show",
  as: :enterprise_multi_tenant_provisioning_request

resources :enterprises, controller: "businesses", param: :slug, only: %i(show destroy) do
  member do
    resource :long_description,
      as: :enterprise_long_description,
      controller: "businesses/long_description",
      only: :update
    resources :organization_counters,
      as: :enterprise_organization_counters,
      controller: "businesses/organization_counters",
      only: :index
    resource :onboarding_tasks,
      as: :enterprise_onboarding_tasks,
      controller: "businesses/onboarding_tasks",
      only: %i(show update)
    resources :organization_settings_menu,
      as: :enterprise_organization_settings_menu,
      controller: "businesses/organization_settings_menu",
      param: :organization,
      only: %i(show)
    resources :org_filter_menu_content,
      as: :enterprise_org_filter_menu_content,
      controller: "businesses/org_filter_menu_content",
      param: :path_type,
      only: %i(show)
    resources :outside_collaborators,
      as: :enterprise_outside_collaborators,
      controller: "businesses/outside_collaborators",
      param: :login,
      only: %i(index show)
    resources :outside_collaborator_details,
      as: :enterprise_outside_collaborator_details,
      controller: "businesses/outside_collaborator_details",
      only: :index
    resources :unowned_organizations,
      as: :enterprise_unowned_organizations,
      controller: "businesses/unowned_organizations",
      param: :login,
      only: %i(index update)
    resources :suspended_members,
      as: :enterprise_suspended_members,
      controller: "businesses/suspended_members",
      only: %i(index)
    resource :invited,
      as: :enterprise_invited,
      controller: "businesses/invited",
      only: %i(show)
    resource "getting-started",
      as: :enterprise_getting_started,
      controller: "businesses/getting_started",
      only: %i(show)
    resource :slug,
      as: :enterprise_slug,
      controller: "businesses/slug",
      only: %i(update)
    get  "people/export/:token", to: "businesses/enterprise_users_export#show", as: :enterprise_users_export
    post "people/export", to: "businesses/enterprise_users_export#create", format: "json"

    resources :people_counts,
      as: :enterprise_people_counts,
      controller: "businesses/people_counts",
      param: :metric,
      only: %i(show)
    resources :license_counts,
      as: :enterprise_license_counts,
      controller: "businesses/license_counts",
      param: :metric,
      only: %i(show)

    get :people, to: "businesses/people#index"
    delete "people/:person_login/", to: "businesses/people#destroy", as: :people_destroy

    get "people/:person_login/organizations", to: "businesses/people/organizations#index", as: :enterprise_person_organizations
    get "people/:person_login/teams", to: "businesses/people/teams#index", as: :enterprise_person_teams
    get "people/:person_login/enterprise_installations", to: "businesses/people/enterprise_installations#index", as: :enterprise_person_enterprise_installations
    get "people/:person_login/sso", to: "businesses/people/sso#index", as: :enterprise_person_sso
    delete "people/:person_login/external_identity", to: "businesses/people/external_identities#destroy", as: :enterprise_person_unlink_identity
    delete "people/:person_login/sso_session/:session_id", to: "businesses/people/sso_sessions#destroy", as: :enterprise_person_revoke_sso_session
    delete "people/:person_login/sso_token/:token_id", to: "businesses/people/credential_authorizations#destroy", as: :enterprise_person_revoke_sso_token

    resources :people_bulk_actions,
      as: :enterprise_people_bulk_actions,
      controller: "businesses/people_bulk_actions",
      param: :bulk_action,
      only: %i(index show create)

    resources :notices,
      as: :enterprise_notices,
      controller: "businesses/notices",
      param: :notice,
      only: %i(update destroy)

    get :external_groups, to: "businesses/identity_provider#external_groups"
    get "external_group_members/:id", to: "businesses/identity_provider#external_group_members", as: :external_group_members
    get "external_group_teams/:id", to: "businesses/identity_provider#external_group_teams", as: :external_group_teams

    resource :available_licenses,
      as: :enterprise_available_licenses,
      controller: "businesses/available_licenses",
      only: %i(show)

    resources :member_details,
      as: :enterprise_member_details,
      controller: "businesses/member_details",
      only: :index

    resources :admins,
      as: :enterprise_admins,
      controller: "businesses/admins",
      param: :admin,
      only: %i(index create destroy) do
      member do
        patch :role, to: "businesses/admin_roles#update"
      end
    end

    resources :admin_suggestions,
      as: :enterprise_admin_suggestions,
      controller: "businesses/admin_suggestions",
      only: %w(index)

    resources :admin_details,
      as: :enterprise_admin_details,
      controller: "businesses/admin_details",
      only: :index

    resources :pending_members,
      as: :enterprise_pending_members,
      controller: "businesses/pending_members",
      param: :login,
      only: %i(index show)
    resource :cancelable_pending_members,
      as: :enterprise_cancelable_pending_members,
      controller: "businesses/cancelable_pending_members",
      only: %i(destroy)
    resources :pending_admins,
      as: :enterprise_pending_admins,
      controller: "businesses/pending_admins",
      param: :login,
      only: %i(index show)
    resource :cancelable_pending_admins,
      as: :enterprise_cancelable_pending_admins,
      controller: "businesses/cancelable_pending_admins",
      only: %i(destroy)
    resources :pending_collaborators,
      as: :enterprise_pending_collaborators,
      controller: "businesses/pending_collaborators",
      param: :login,
      only: %i(index show)
    resource :cancelable_pending_collaborators,
      as: :enterprise_cancelable_pending_collaborators,
      controller: "businesses/cancelable_pending_collaborators",
      only: %i(destroy)
    resources :pending_unaffiliated_members,
      as: :enterprise_pending_unaffiliated_members,
      controller: "businesses/pending_unaffiliated_members",
      only: %i(index destroy)
    resource :cancelable_pending_unaffiliated_members,
      as: :enterprise_cancelable_pending_unaffiliated_members,
      controller: "businesses/cancelable_pending_unaffiliated_members",
      only: %i(destroy)

    # For creating and destroying admin invitations
    resources :admin_invitations,
      as: :enterprise_admin_invitations,
      controller: "businesses/admin_invitations",
      param: :invitation_id,
      only: %i(create destroy)

    # For viewing and accepting owner invitations
    resource :owner_invitation,
      as: :enterprise_owner_invitation,
      controller: "businesses/owner_invitations",
      only: %i(show update)
    # Temporary redirect for legacy invitation URLs
    get "admin_invitation",
      as: :enterprise_owner_invitation_redirect,
      to: redirect("/enterprises/%{slug}/owner_invitation")

    # For viewing and accepting billing manager invitations
    resource :billing_manager_invitation,
      as: :enterprise_billing_manager_invitation,
      controller: "businesses/billing_manager_invitations",
      only: %i(show update)

    # For viewing and accepting unaffiliated member invitations
    resource :member_invitation,
      as: :enterprise_member_invitation,
      controller: "businesses/member_invitations",
      only: %i(show create update) do
      get :invitee_suggestions, action: :invitee_suggestions, as: "invitee_suggestions"
    end

    resource :member_invitee_suggestions,
      as: :enterprise_member_invitee_suggestions,
      controller: "businesses/member_invitee_suggestions",
      only: %i(show)

    resource :member_invitations,
      as: :enterprise_organization_member_invitations,
      controller: "businesses/organization_member_invitations",
      only: :destroy

    resource :pending_invitation_actions,
      as: :enterprise_pending_invitation_actions,
      controller: "businesses/pending_invitation_actions",
      only: :show

    resource :cancel_pending_invitations_dialog,
      as: :enterprise_cancel_pending_invitations_dialog,
      controller: "businesses/cancel_pending_invitations_dialog",
      only: :show

    resource :failed_invitations,
      as: :enterprise_failed_invitations,
      controller: "businesses/organization_failed_invitations",
      only: %i(show update destroy)

    resource :failed_invitation_actions,
      as: :enterprise_failed_invitation_actions,
      controller: "businesses/failed_invitation_actions",
      only: :show

    resource :failed_invitations_action_dialog,
      as: :enterprise_failed_invitations_action_dialog,
      controller: "businesses/failed_invitations_action_dialog",
      only: :show

    get "data", to: "businesses/data_packs#index", as: :data_packs
    put "data", to: "businesses/data_packs#update"

    get "pending_organizations", to: "businesses/organization_invitations#index"
    resources :enterprise_organization_invitations,
      path: "organization_invitations",
      controller: "businesses/organization_invitations",
      param: :organization_login,
      only: %i(new create) do
      get "suggestions", on: :collection, to: "businesses/organization_invitations/suggestions#index"
      member do
        post "pending/accept", to: "businesses/organization_invitations/acceptances#create", as: "accept_pending"
        post "pending/cancel", to: "businesses/organization_invitations/cancellations#create", as: "cancel_pending"
        post "pending/confirm", to: "businesses/organization_invitations/confirmations#create", as: "confirm_pending"
        post "pending/resend", to: "businesses/organization_invitations/resends#create", as: "resend_pending"
      end
    end

    resources :trial_activations,
      as: :enterprise_trial_activations,
      controller: "businesses/trial_activations",
      only: [:index, :create]

    resources :user_namespace_repositories, as: :enterprise_user_namespace_repositories,
      controller: "businesses/user_namespace_repositories", param: :repository_id, only: [:index, :update]

    delete "removed_member_notifications", to: "businesses/removed_member_notifications#destroy", as: :destroy_removed_member_notifications

    resources :insights, as: :enterprise_insights, controller: "businesses/insights", only: [:index] do
      collection do
        get :settings
        post :base_url, action: :update_base_url
      end
    end

    get "security", to: redirect(path: "/enterprises/%{slug}/security/risk", status: 302)
    get "security/risk", to: "businesses/security_center/risk#index", as: :security_center_risk
    get "security/risk/stats", to: "businesses/security_center/risk#stats", as: :security_center_risk_stats
    get "security/risk/counts", to: "businesses/security_center/risk#counts", as: :security_center_risk_counts
    get "/security/risk/export", to: "businesses/security_center/risk_export#show", format: :csv, as: :security_center_risk_get_export
    post "/security/risk/export", to: "businesses/security_center/risk_export#create", format: :json, as: :security_center_risk_create_export
    get "security/coverage", to: "businesses/security_center/coverage#index", as: :security_center_coverage
    get "security/coverage/stats", to: "businesses/security_center/coverage#stats", as: :security_center_coverage_stats
    get "security/coverage/counts", to: "businesses/security_center/coverage#counts", as: :security_center_coverage_counts
    get "/security/coverage/export", to: "businesses/security_center/coverage_export#show", format: :csv, as: :security_center_coverage_get_export
    post "/security/coverage/export", to: "businesses/security_center/coverage_export#create", format: :json, as: :security_center_coverage_create_export
    get "security/alerts/secret-scanning", to: "businesses/security_center/secret_scanning#index", as: :security_center_alerts_secret_scanning
    get "security/alerts/secret-scanning/filter-suggestions", to: "businesses/security_center/secret_scanning#alerts_get_filter_input_suggestions", as: :security_center_alerts_secret_scanning_alerts_get_filter_input_suggestions
    get "security/alerts/secret-scanning/menu-content", to: "businesses/security_center/secret_scanning#menu_content", as: :security_center_alerts_secret_scanning_menu_content
    get "security/alerts/dependabot", to: "businesses/security_center/dependabot_alerts#index", as: :security_center_alerts_dependabot
    get "security/alerts/dependabot/menu-content", to: "businesses/security_center/dependabot_alerts#menu_content", as: :security_center_alerts_dependabot_menu_content
    get "security/alerts/dependabot/filter-input-suggestions", to: "businesses/security_center/dependabot_alerts#filter_input_suggestions", as: :security_center_alerts_dependabot_filter_input_suggestions
    get "security/alerts/code-scanning", to: "businesses/security_center/code_scanning#index", as: :security_center_alerts_code_scanning
    get "security/alerts/code-scanning/menu-content", to: "businesses/security_center/code_scanning#menu_content", as: :security_center_code_scanning_menu_content
    get "security/alerts/code-scanning/filter-input-suggestions", to: "businesses/security_center/code_scanning#filter_input_suggestions", as: :security_center_alerts_code_scanning_filter_input_suggestions
    get "security/options", to: "businesses/security_center/options#index", as: :security_center_options

    scope "/security", module: "businesses/security_center", as: :enterprise_security_center do
      resource :overview, controller: :overview_dashboard, only: [], as: :overview_dashboard do
        get :index

        defaults format: :json do
          get :advisories
          get :"age-of-alerts"
          get :"alert-activity"
          get :"introduced-prevented"
          get :"alert-trends-by-age"
          get :"alert-trends-by-severity"
          get :"alert-trends-by-tool-code-scanning"
          get :"alert-trends-by-tool-dependabot-alerts"
          get :"alert-trends-by-tool-secret-scanning"
          get :"mean-time-to-remediate"
          get :"net-resolve-rate"
          get :"reopened-alerts"
          get :repositories
          get :sast
          get :"secrets-bypassed"
          get :"pull-request-alerts-fixed"
          get :"alerts-fixed-with-autofix"
          get :"historical-alerts-fixed-with-autofix"
        end

        resource :export, controller: :overview_dashboard_export, only: [:show, :create]
      end

      namespace :metrics do
        resource :enablement, controller: :enablement_trends, only: [] do
          get :index
          get :"enablement-trends", format: :json
        end

        resource :codeql, controller: :code_scanning, only: [] do
          get :index

          defaults format: :json do
            get :"alerts-found"
            get :"autofix-suggestions"
            get :"alerts-fixed"
            get :"alert-trends-by-status"
            get :"alert-trends-by-severity"
            get :"alerts-fixed-with-autofix"
            get :"remediation-rates"
            get :"remediation-time"
            get :"most-prevalent-rules"
            get :repositories
          end

          resource :export, controller: :code_scanning_export, only: [:show, :create]
        end

        resource :"secret-scanning", controller: :secret_scanning, only: [], as: :secret_scanning do
          get :index

          defaults format: :json do
            get :"push-protection-metrics"
            get "/push-protection-metrics/block-counts-by-token-type", action: :block_counts_by_token_type
            get "/push-protection-metrics/block-counts-by-repo", action: :block_counts_by_repo
            get "/push-protection-metrics/bypass-counts-by-token-type", action: :bypass_counts_by_token_type
            get "/push-protection-metrics/bypass-counts-by-repo", action: :bypass_counts_by_repo
          end
        end
      end
    end

    get "settings", to: redirect("/enterprises/%{slug}/settings/profile")

    scope module: "businesses" do
      resource :billing, as: "enterprise_billing", only: [:show] do
        scope module: :billing do
          resource :usage, only: :show do
            get "/repo", to: "repo_usage#show", as: :org
            get "/total", to: "usage_totals#show"
          end

          get "/net_usage", to: "net_usages#index"
          get "/usage_chart", to: "usage_chart#index"
          get "/usage_table", to: "usage_table#index"
          get "/cost_centers_list", to: "cost_centers#list"
          get "/copilot_premium_usage_report", to: "copilot_premium_usage_report#show"

          resources :usage_report, only: [:create, :show]
          resources :budgets
          resources :cost_centers
          resources :products, only: [:index]
          resources :skus, only: [:index]
          resources :discounts, only: [:index]
          resources :payment_history, only: [:index]
          resources :sponsorships, only: [:index]
          resource :payment_information, only: [:show]
          resources :contacts
          resources :marketplace_apps, only: [:index]
          resources :past_invoices, only: [:index]
          resources :shipping_information, only: [:create, :update]
        end
      end
    end

    scope :settings do
      get "copilot_plan_change", to: "businesses/copilot/plan_change#show", as: :settings_copilot_plan_change
      get "copilot", to: "businesses/copilot_settings#index", as: :settings_copilot
      put "copilot_content_exclusion", to: "businesses/copilot_settings#update_content_exclusion", as: :update_settings_copilot_content_exclusion
      put "update_copilot_policy", to: "businesses/copilot_settings#update", as: :update_settings_copilot_policy
      put "update_copilot_enablement", to: "businesses/copilot_settings#update_copilot_enablement", as: :update_settings_copilot_enablement
      put "update_copilot_individual_org_enablement", to: "businesses/copilot_settings#update_individual_org_enablement", as: :update_settings_copilot_individual_org_enablement
      put "update_copilot_bulk_org_enablement", to: "businesses/copilot_settings#update_bulk_org_enablement", as: :update_settings_copilot_bulk_org_enablement
      get "download_seat_management_usage", to: "businesses/copilot_settings#download_seat_management_usage", as: :download_seat_management_usage
      post "search_copilot_orgs", to: "businesses/copilot_settings#search_orgs", as: :search_settings_copilot_orgs_enablement
      get "search_copilot_orgs", to: "businesses/copilot_settings#search_orgs", as: :get_search_settings_copilot_orgs_enablement
      get "enable_copilot", to: "businesses/copilot_settings#show_first_run_flow_cta", as: :settings_copilot_first_run_flow_cta
      get "codespaces", to: "businesses/codespaces_settings#index", as: :settings_codespaces
      get "codespaces/policies", to: "businesses/codespaces/policy_groups#index", as: :settings_codespaces_policies
      get "codespaces/policies/new", to: "businesses/codespaces/policy_groups#new", as: :settings_codespaces_new_policy_group
      post "codespaces/policies", to: "businesses/codespaces/policy_groups#create", as: :settings_codespaces_create_policy_group
      delete "codespaces/policies/:identifier", to: "businesses/codespaces/policy_groups#destroy", as: :settings_codespaces_delete_policy_group
      get "codespaces/policies/add_constraint_dropdown", to: "businesses/codespaces/policy_groups#add_constraint_dropdown", as: :settings_codespaces_add_constraint_dropdown
      get "codespaces/policies/host_setup_repository_select", to: "businesses/codespaces/policy_groups#host_setup_repository_select", as: :settings_codespaces_host_setup_repository_select
      get "codespaces/policies/org_dialog_list", to: "businesses/codespaces/policy_groups#org_dialog_list", as: :settings_codespaces_org_dialog_list
      get "codespaces/policies/:identifier", to: "businesses/codespaces/policy_groups#edit", as: :settings_codespaces_edit_policy_group
      put "codespaces/policies/:identifier", to: "businesses/codespaces/policy_groups#update", as: :settings_codespaces_update_policy_group
      put "update_codespaces_org_enablement", to: "businesses/codespaces_settings#update_org_enablement", as: :update_settings_codespaces_org_enablement
      post "search_codespaces_orgs", to: "businesses/codespaces_settings#search_orgs", as: :search_settings_codespaces_orgs_enablement
      get "search_codespaces_orgs", to: "businesses/codespaces_settings#search_orgs", as: :get_search_settings_codespaces_orgs_enablement
      resource "linked_accounts",
        as: :settings_linked_accounts_enterprise,
        controller: "businesses/linked_accounts",
        only: [:show, :update]
      get "profile", to: "businesses/profiles#show", as: :settings_profile
      put "profile", to: "businesses/profiles#update"
      get "profile_footer", to: "businesses/profiles_footer#show", as: :settings_profile_footer
      put "profile_footer", to: "businesses/profiles_footer#update"
      get "member_privileges", to: "businesses/member_privileges#index", as: :settings_member_privileges
      get "custom-properties", to: "businesses/custom_properties_settings#index", as: :settings_custom_properties
      post "custom-properties", to: "businesses/custom_properties_settings#create", as: :business_custom_properties_create, format: :json
      get "custom-property/(:property_name)", to: "businesses/custom_properties_settings#show", as: :business_custom_properties_show
      delete "custom-property/:property_name", to: "businesses/custom_properties_settings#destroy", as: :business_custom_properties_destroy
      get "custom-properties-usage/:property_name", to: "businesses/custom_properties_settings#check_usage", as: :business_custom_properties_usage
      get "custom-property/organizations/:organization_login/:property_name", to: "businesses/orgs_custom_properties_settings#show", as: :org_in_business_custom_properties_show
      post "custom-property/organizations/:organization_login/:property_name/promote", to: "businesses/orgs_custom_properties_settings#promote", as: :org_in_business_custom_properties_promote, format: :json
      resources :property_definition_name_check, controller: "businesses/property_definition_name_check", param: :property_name, only: [:show]
      put "update_members_can_change_repo_visibility", to: "businesses/members_can_change_repo_visibility#update", as: :update_members_can_change_repo_visibility
      put "update_default_branch_setting", to: "businesses/default_branch_setting#update", as: :update_default_branch_setting
      put "update_deploy_key_policy", to: "businesses/deploy_keys#update", as: :update_deploy_key_policy
      put "update_allow_private_repository_forking", to: "businesses/private_repository_forking#update", as: :update_allow_private_repository_forking
      put "members_can_create_repositories", to: "businesses/member_repository_creation#update", as: :settings_members_can_create_repositories
      put "members_can_delete_repositories", to: "businesses/member_repository_deletion#update", as: :settings_members_can_delete_repositories
      put "members_can_delete_issues", to: "businesses/member_issue_deletion#update", as: :settings_members_can_delete_issues
      put "members_can_update_protected_branches", to: "businesses/member_protected_branches_updates#update", as: :settings_members_can_update_protected_branches
      put "members_can_invite_outside_collaborators", to: "businesses/members_can_invite_outside_collaborators#update", as: :settings_members_can_invite_outside_collaborators
      put "default_repository_permission", to: "businesses/default_repository_permission#update", as: :update_default_repository_permission
      put "restrict_repository_create_in_personal_namespace", to: "businesses/member_personal_namespace_repository_creation#update", as: :restrict_repository_create_in_personal_namespace

      # rulesets
      get    "/policies/repositories",                                to: "businesses/repository_policies#ruleset_index",  as: :settings_repository_policies
      get    "/policies/repositories/new",                            to: "businesses/repository_policies#ruleset_new"
      get    "/policies/repositories/:id/history",                    to: "businesses/repository_policies#ruleset_history_summary"
      get    "/policies/repositories/:id/history/:history_id/compare(/:compare_history_id)", to: "businesses/repository_policies#ruleset_history_comparison"
      get    "/policies/repositories/:id/history/:history_id/view",   to: "businesses/repository_policies#ruleset_history_view", as: :settings_repository_policies_history
      post   "/policies/repositories/validate_value/:type",           to: "businesses/repository_policies#ruleset_validate_value"
      get    "/policies/repositories/:id/bypass_suggestions",         to: "businesses/repository_policies#ruleset_bypass_suggestions"
      get    "/policies/repositories/available_properties",           to: "businesses/repository_policies#ruleset_available_properties"
      get    "/policies/repositories/:id/repo_suggestions",           to: "businesses/repository_policies#ruleset_repo_suggestions"
      get    "/policies/repositories/:id/org_suggestions",            to: "businesses/repository_policies#ruleset_org_suggestions"
      get    "/policies/repositories/:id",                            to: "businesses/repository_policies#ruleset_show", as: :settings_repository_policy
      post   "/policies/repositories/:id",                            to: "businesses/repository_policies#ruleset_update"
      delete "/policies/repositories/:id",                            to: "businesses/repository_policies#ruleset_destroy"

      get    "/policies/code/bypass_requests",                to: "businesses/code_rules_bypass_requests#index",                      as: :settings_code_rules_bypass_requests
      get    "/policies/code/bypass_requests/requesters",     to: "businesses/code_rules_bypass_requests#bypass_request_requesters",  as: :settings_code_rules_bypass_request_requesters
      get    "/policies/code/bypass_requests/approvers",      to: "businesses/code_rules_bypass_requests#bypass_request_approvers",   as: :settings_code_rules_bypass_request_approvers
      get    "/policies/code/insights",                       to: "businesses/code_rulesets#rule_insights",             as: :settings_code_rule_insights
      get    "/policies/code/insights/actors",                to: "businesses/code_rulesets#rule_insights_actors",      as: :settings_code_rule_insights_actors
      get    "/policies/code",                                to: "businesses/code_rulesets#ruleset_index",  as: :settings_code_rules
      get    "/policies/code/new",                            to: "businesses/code_rulesets#ruleset_new"
      get    "/policies/code/:id/history",                    to: "businesses/code_rulesets#ruleset_history_summary"
      get    "/policies/code/:id/history/:history_id/compare(/:compare_history_id)", to: "businesses/code_rulesets#ruleset_history_comparison"
      get    "/policies/code/:id/history/:history_id/view",   to: "businesses/code_rulesets#ruleset_history_view", as: :settings_code_view_ruleset_history
      post   "/policies/code/validate_value/:type",           to: "businesses/code_rulesets#ruleset_validate_value"
      get    "/policies/code/:id/bypass_suggestions",         to: "businesses/code_rulesets#ruleset_bypass_suggestions"
      get    "/policies/code/available_properties",           to: "businesses/code_rulesets#ruleset_available_properties"
      get    "/policies/code/workflows",                      to: "businesses/code_rulesets#get_workflows_content"
      get    "/policies/code/:id/org_suggestions",            to: "businesses/code_rulesets#ruleset_org_suggestions"
      get    "/policies/code/:id",                            to: "businesses/code_rulesets#ruleset_show", as: :settings_code_ruleset
      post   "/policies/code/:id",                            to: "businesses/code_rulesets#ruleset_update"
      delete "/policies/code/:id",                            to: "businesses/code_rulesets#ruleset_destroy"
      get    "/policies/code/:id/export_ruleset",             to: "businesses/code_rulesets#export_ruleset"
      get    "/policies/code/:id/export_ruleset/:history_id", to: "businesses/code_rulesets#export_ruleset"

      get "packages_migration", to: "businesses/packages_migration#show", as: :settings_packages_migration
      post "packages_migration", to: "businesses/packages_migration#trigger_namespace_migration", as: :packages_migration
      put "packages_migration", to: "businesses/packages_migration#hide_progress_message_when_closed", as: :hide_in_progress_message
      get "packages_migration/update_progress_bar", to: "businesses/packages_migration#update_progress_bar", as: :update_progress_bar
      get "packages_migration/reload_package_settings", to: "businesses/packages_migration#reload_package_settings_section", as: :reload_package_settings
      get "packages_migration/show_message", to: "businesses/packages_migration#show_flash_message", as: :show_flash_message
      get "packages_migration/success_message_close", to: "businesses/packages_migration#hide_success_message", as: :hide_success_message
      get "packages_migration/progress_message_after_migration", to: "businesses/packages_migration#hide_progress_message_after_migration", as: :progress_message_after_migration

      scope path: "/personal-access-tokens" do
        get "/",                        to: "businesses/personal_access_token_policies#index",                         as: :settings_personal_access_tokens
        get "/classic",                 to: "businesses/personal_access_token_policies/classics#index",                as: :settings_classic_personal_access_tokens
        patch "restrict-access",        to: "businesses/personal_access_token_policies/restrict_access#update",        as: :settings_restrict_pat_access
        patch "maximum-lifetime",       to: "businesses/personal_access_token_policies/maximum_lifetimes#update",      as: :settings_maximum_lifetime
        patch "restrict-legacy-access", to: "businesses/personal_access_token_policies/restrict_legacy_access#update", as: :settings_restrict_legacy_pat_access
      end

      scope path: "/personal-access-token-requests" do
        patch "/auto-approvals", to: "businesses/personal_access_token_request_policies/auto_approvals#update", as: :settings_pat_auto_approvals
      end

      scope controller: "businesses/personal_access_token_policies/onboarding" do
        get   "/personal-access-tokens-onboarding", action: :edit,  as: :settings_personal_access_tokens_onboarding
        patch "/personal-access-tokens-onboarding", action: :update
      end

      put "members_can_view_dependency_insights", to: "businesses/organizations#update_members_can_view_dependency_insights", as: :update_members_can_view_dependency_insights

      post "metered_exports",     to: "businesses/metered_exports#create",      as: "metered_exports"
      get  "metered_exports/:id", to: "businesses/metered_exports#show",        as: "metered_export"
      get "billing", to: "businesses/billing_settings#show", as: :settings_billing

      patch "accept_gca", to: "businesses/terms_of_service#update", as: :accept_gca
      get "billing/activations", to: "businesses/activations#index", as: :settings_billing_activations
      put "billing/cancel_trial", to: "businesses/billing_settings#cancel_trial", as: :settings_billing_cancel_trial
      put "billing/cancel_addon_trial", to: "businesses/billing_settings#cancel_addon_trial", as: :settings_billing_cancel_addon_trial
      put "billing/convert_trial", to: "businesses/billing_settings#convert_trial", as: :settings_billing_convert_trial
      put "billing/multi_checkout", to: "businesses/multi_checkout#update", as: :settings_billing_multi_checkout
      get "billing/renew", to: "businesses/billing/renewals#new"
      post "billing/renew", to: "businesses/billing/renewals#create"
      get "billing/add_seats", to: "businesses/billing/renewals#edit"
      post "billing/add_seats", to: "businesses/billing/renewals#create"
      get "billing/upgrade", to: "businesses/billing/upgrades#new"
      post "billing/upgrade", to: "businesses/billing/upgrades#create"
      get "billing/upgrade_from_organization", to: "businesses/upgrade_from_organization#new"
      put "billing/upgrade_from_organization", to: "businesses/upgrade_from_organization#create"
      delete "billing/upgrade_from_organization", to: "businesses/upgrade_from_organization#destroy"
      get "advanced_security_orgs_list/:page", to: "businesses/advanced_security#advanced_security_orgs_list", as: :settings_business_advanced_security_orgs_list, constraints: { page: /\d+/ }
      get "advanced_security_users_list/:page", to: "businesses/advanced_security#advanced_security_users_list", as: :settings_business_advanced_security_users_list, constraints: { page: /\d+/ }
      get "actions_usage", to: "businesses/billing_settings/shared_products_usage#show_actions", as: :settings_billing_actions_usage
      get "codespaces_usage", to: "businesses/billing_settings/codespaces_usage#show_org_usage", as: :settings_billing_codespaces_org_usage
      get "codespaces_overview", to: "businesses/billing_settings/codespaces_usage#show_overview", as: :settings_billing_codespaces_overview
      get "copilot_usage", to: "businesses/billing_settings/copilot_usage#show", as: :settings_billing_copilot_usage
      get "metered_usage", to: "businesses/billing_settings/metered_usage#show", as: :settings_billing_metered_usage
      get "packages_usage", to: "businesses/billing_settings/shared_products_usage#show_packages", as: :settings_billing_packages_usage
      get "shared_storage_overview", to: "businesses/billing_settings/shared_products_usage#show_shared_storage_overview", as: :settings_billing_shared_storage_overview
      get "packages_storage/:page", to: "businesses/billing_settings/shared_products_usage#show_packages_storage", as: :settings_billing_packages_storage, constraints: { page: /\d+/ }
      get "shared_storage/:page", to: "businesses/billing_settings/shared_products_usage#show_shared_storage", as: :settings_billing_shared_storage, constraints: { page: /\d+/ }
      get "lfs_usage", to: "businesses/billing_settings/lfs_usage#show", as: :settings_billing_lfs_usage
      get "usage_notification", to: "businesses/billing_settings/usage_notifications#show", as: :settings_billing_usage_notification
      get "billing/cost_management", to: redirect("/enterprises/%{slug}/settings/billing/spending_limit")
      get "billing/:tab", to: "businesses/billing_settings#show", as: :settings_billing_tab, tab: /cost_management|billing_emails|past_invoices|spending_limit|budgets|marketplace_apps|sponsorships|payment_information/
      get "billing/payment_information/authenticate", to: "businesses/billing_settings#authenticate_azure"
      post "billing/cost_management", to: "businesses/metered_billing_costs#update", as: :metered_billing_costs
      post "billing/cost_management/usage_notification_settings", to: "businesses/metered_billing_costs#usage_notification_settings", as: :metered_billing_costs_usage_notification_settings
      get "billing/marketplace_apps/:page", to: "businesses/billing_settings/marketplace_apps#show", as: :settings_billing_marketplace_apps, constraints: { page: /\d+/ }
      put "billing/members_can_make_purchases", to: "businesses/billing_settings#update_members_can_make_purchases", as: :billing_settings_members_can_make_purchases
      get "billing/one_time_payment", to: "businesses/one_time_payment#new", as: :billing_settings_one_time_payment
      put "billing/update_payment_information", to: "businesses/billing_settings#update_payment_information", as: :billing_settings_update_payment_information
      post "billing/update_payment_method", to: "businesses/billing_settings#update_payment_method", as: :billing_settings_update_payment_method
      post "billing/redeeem_coupon", to: "coupons#redeem", as: :billing_settings_redeeem_coupon
      get "billing/payment_history", to: "businesses/billing_settings#payment_history", as: :billing_settings_payment_history

      get "billing/edit_multi_checkout", to: "businesses/multi_checkout#edit", as: :edit_multi_checkout
      put "billing/change_seats", to: "businesses/seats#update", as: :billing_settings_change_seats
      get "billing/seat_price", to: "businesses/seats#show", as: :billing_settings_seat_price
      get "billing/advanced_security/upgrade", to: "businesses/advanced_security/upgrade#show", as: :billing_settings_advanced_security_upgrade
      put "billing/advanced_security/subscribe", to: "businesses/advanced_security/upgrade#update", as: :billing_settings_advanced_security_subscribe
      put "billing/advanced_security/change_seats", to: "businesses/advanced_security/seats#update", as: :billing_settings_advanced_security_change_seats
      get "billing/advanced_security/seat_price", to: "businesses/advanced_security/seats#show", as: :billing_settings_advanced_security_seat_price
      put "billing/update_metered_via_azure", to: "businesses/billing_settings#update_metered_via_azure", as: :billing_settings_update_metered_via_azure

      scope module: :businesses do
        namespace :advanced_security do
          resource :subscriptions, only: [:update]
          resource :cancel_subscriptions, only: [:show]
          resource :trials, only: [:create]
          namespace :suggestion_flow do
            resource :organizations, only: [:show, :update]
            resource :repositories, only: [:show, :update]
            resource :requests, only: [:show, :create]
          end
        end
      end

      resources :virtual_networks, as: :settings_virtual_networks, controller: "businesses/virtual_network_settings"

      resources :network_configurations, as: :settings_network_configurations, controller: "businesses/network_configurations", only: [:index] do
        collection do
          get "azure_private_network/new", to: "businesses/network_configurations#new_private_network", as: :new_private_network
          put "azure_private_network/new", to: "businesses/network_configurations#validate_private_network", as: :validate_private_network
          get "find", to: "businesses/network_configurations#find", as: :find
          get ":network_configuration_id", to: "businesses/network_configurations#show", as: :show
          get ":network_configuration_id/edit", to: "businesses/network_configurations#edit", as: :edit
          post "update", to: "businesses/network_configurations#update", as: :update
          delete "remove", to: "businesses/network_configurations#remove", as: :remove
        end
      end

      resource :hosted_compute_networking,
        as: :enterprise_hosted_compute_networking,
        controller: "businesses/hosted_compute_networking",
        only: %i(show update)

      resources :billing_email, controller: "businesses/billing_settings/billing_emails", only: [:create, :destroy], as: :enterprise_billing_emails, target: "business" do
        collection do
          put "update_primary", to: "businesses/billing_settings/billing_emails#update_primary", as: :update_primary
          put "mark_primary/:id", to: "businesses/billing_settings/billing_emails#mark_primary", as: :mark_primary
        end
      end

      resources :billing_budget, controller: "businesses/billing_budgets", only: [:index, :new, :create, :destroy, :update, :edit], as: :billing_settings_billing_budget

      get "advanced_security",                            to: redirect("/enterprises/%{slug}/settings/security_analysis_policies")
      get "security_analysis_policies",                   to: "businesses/security_analysis_policies#index",                    as: :settings_security_analysis_policies
      get "advanced_security/security_features",          to: redirect("/enterprises/%{slug}/settings/security_analysis_policies/security_features")
      get "security_analysis_policies/security_features", to: "businesses/security_analysis_policies#index_security_features",  as: :settings_security_analysis_policies_security_features
      put "security_analysis_policies/update_ghas_availability",       to: "businesses/security_analysis_policies#update_ghas_availability",      as: :settings_security_analysis_policies_update_ghas_availability
      put "security_analysis_policies/update_org_ghas_availability",   to: "businesses/security_analysis_policies#update_org_ghas_availability",  as: :settings_security_analysis_policies_update_org_ghas_availability
      put "security_analysis_policies/update_org_ghas_sku_availability",   to: "businesses/security_analysis_policies#update_org_ghas_sku_availability",  as: :settings_security_analysis_policies_update_org_ghas_sku_availability
      put "security_analysis_policies/update_ghas_enablement",              to: "businesses/security_analysis_policies#update_ghas_enablement",               as: :settings_security_analysis_policies_update_ghas_enablement
      put "security_analysis_policies/update_ghas_code_security_enablement", to: "businesses/security_analysis_policies#update_ghas_code_security_enablement", as: :settings_security_analysis_policies_update_ghas_code_security_enablement
      put "security_analysis_policies/update_dependabot_alerts_enablement", to: "businesses/security_analysis_policies#update_dependabot_alerts_enablement",  as: :settings_security_analysis_policies_update_dependabot_alerts_enablement
      put "security_analysis_policies/update_secret_scanning_settings",     to: "businesses/security_analysis_policies#update_secret_scanning_settings",      as: :settings_security_analysis_policies_update_secret_scanning_settings
      put "security_analysis_policies/update_generic_secrets_settings",     to: "businesses/security_analysis_policies#update_generic_secrets_settings",      as: :settings_security_analysis_policies_update_generic_secrets_settings
      put "security_analysis_policies/update_dependency_insights_settings",     to: "businesses/security_analysis_policies#update_dependency_insights_view_permissions",      as: :settings_security_analysis_policies_update_dependency_insights_view_permissions
      put "security_analysis_policies/code_scanning_autofix/:policy", to: "businesses/code_scanning_autofix_policies#update", as: :settings_code_scanning_autofix_policy

      # Secret Scanning Custom Patterns

      # Active routes
      get    "advanced_security/custom_patterns/new", to: "businesses/custom_patterns#new_custom_pattern", as: :settings_business_new_custom_pattern
      post   "advanced_security/custom_patterns/new", to: "businesses/custom_patterns#create_custom_pattern", as: :settings_business_create_custom_pattern
      delete "advanced_security/custom_patterns", to: "businesses/custom_patterns#delete_custom_patterns", as: :settings_business_delete_custom_patterns
      post   "advanced_security/test_custom_secret_scanning_pattern", to: "businesses/custom_patterns#test_custom_secret_scanning_pattern", as: :settings_business_test_custom_secret_scanning_pattern
      post   "advanced_security/custom_patterns/get_generated_expressions", to: "businesses/custom_patterns#get_generated_expressions", as: :settings_business_get_generated_expressions

      constraints id: /\d+/ do
        get    "advanced_security/custom_patterns/:id", to: "businesses/custom_patterns#show_custom_pattern", as: :settings_business_show_custom_pattern
        post   "advanced_security/custom_patterns/:id", to: "businesses/custom_patterns#update_custom_pattern", as: :settings_business_update_custom_pattern
        post   "advanced_security/custom_patterns/:id/settings", to: "businesses/custom_patterns#update_custom_pattern_settings", as: :settings_business_update_custom_pattern_settings
        delete "advanced_security/custom_patterns/:id", to: "businesses/custom_patterns#delete_custom_pattern", as: :settings_business_delete_custom_pattern
        post   "advanced_security/custom_patterns/:id/cancel_dry_run", to: "businesses/custom_patterns#cancel_custom_pattern_dry_run", as: :settings_business_cancel_custom_pattern_dry_run
        get    "advanced_security/get_custom_pattern_form_actions/:id", to: "businesses/custom_patterns#get_custom_pattern_form_actions", as: :settings_business_get_custom_pattern_form_actions
        get    "advanced_security/get_custom_pattern_dry_run_results_by_cursor/:id", to: "businesses/custom_patterns#get_custom_pattern_dry_run_results_by_cursor", as: :settings_business_get_custom_pattern_dry_run_results_by_cursor
        get    "advanced_security/custom_patterns/:id/metrics/alerts", to: "businesses/custom_patterns#get_alert_metrics", as: :settings_business_get_custom_pattern_alert_metrics
        get    "advanced_security/custom_patterns/:id/metrics/push_protection", to: "businesses/custom_patterns#get_push_protection_metrics", as: :settings_business_get_custom_pattern_push_protection_metrics
      end

      # Internal routes
      get  "advanced_security/custom_patterns/dry_run_repository_suggestions", to: "businesses/custom_patterns#dry_run_repository_suggestions", as: :settings_business_dry_run_repository_suggestions
      post  "advanced_security/custom_patterns/dry_run_update_selected_repositories", to: "businesses/custom_patterns#dry_run_update_selected_repositories", as: :settings_business_dry_run_update_selected_repositories

      # Deprecated routes - retained for redirection in case users have bookmarked links.
      get    "advanced_security/new_custom_secret_scanning_pattern", to: redirect("advanced_security/custom_patterns/new")
      get    "advanced_security/edit_custom_secret_scanning_pattern/:id", to: redirect("advanced_security/custom_patterns/:id")

      resources :azure_tenants, controller: "businesses/azure_tenants", only: [:index], as: :billing_settings_azure_tenants
      resources :azure_subscriptions, controller: "businesses/azure_subscriptions", only: [:index], as: :billing_settings_azure_subscriptions
      resource :azure_selected_subscription, controller: "businesses/azure_selected_subscription", only: [:destroy, :update], as: :billing_settings_selected_azure_subscription

      get "billing/invoices/:invoice_number", to: "invoices#show", as: :show_invoice
      get "billing/invoices/:invoice_number/pay", to: "invoices#pay", as: :pay_invoice
      get "billing/invoices/:invoice_number/payment_method", to: "invoices#payment_method", as: :invoice_payment_method
      get "billing/invoices/:invoice_number/signature", to: "invoices#payment_page_signature", as: :invoice_signature

      if GitHub.licensed_mode?
        get "license", to: "businesses/licenses#index", as: :settings_license
        get "license/download", to: "businesses/licenses#download", as: :settings_license_download
        post "license/manual_sync", to: "businesses/licenses#manual_sync", as: :settings_license_manual_sync
      end

      get "audit-log", to: "businesses/audit_log#index", as: :settings_audit_log
      get "audit-log/results", to: "businesses/audit_log#results", as: :settings_audit_log_results
      get "audit-log/suggestions", to: "businesses/audit_log#suggestions", as: :settings_audit_log_suggestions
      get "audit-log/export", to: "businesses/audit_log#export", as: :settings_audit_log_export
      get "audit-log/export_status", to: "businesses/audit_log#export_status", as: :settings_audit_log_export_status
      post "audit-log/export(.:format)", to: "businesses/audit_log#create_export", as: :settings_audit_log_create_web_export
      get  "audit-log/export-git", to: "businesses/audit_log#git_export", as: :settings_audit_log_git_event_export
      get "audit-log/export-git-status", to: "businesses/audit_log#git_event_export_status", as: :settings_audit_log_git_event_export_status
      post "audit-log/export-git(.:format)", to: "businesses/audit_log#create_git_export", as: :settings_audit_log_create_git_export
      scope "/audit-log/stream", as: :settings_audit_log_stream do
        get "", to: "businesses/audit_log_stream#show", as: :show
        put "toggle",  to: "businesses/audit_log_stream#toggle", as: :toggle
        delete "",  to: "businesses/audit_log_stream#remove", as: :remove
        scope do
          get ":type", to: "businesses/audit_log_sink#show_add", as: :show_add
          post ":type/add", to: "businesses/audit_log_sink#check", constraints: lambda { |request| request.parameters[:check_button] }
          post ":type/add", to: "businesses/audit_log_sink#upsert", as: :add
          post ":type/update", to: "businesses/audit_log_sink#check", constraints: lambda { |request| request.parameters[:check_button] }
          post ":type/update", to: "businesses/audit_log_sink#upsert", as: :update
        end
      end

      # Endpoints for supporting multiple endpoints streaming
      scope "/audit-log/streams", as: :settings_audit_log_streams do
        get "", to: "businesses/audit_log_streams#show", as: :show
        put ":id/toggle",  to: "businesses/audit_log_streams#toggle", as: :toggle
        delete ":id",  to: "businesses/audit_log_streams#remove", as: :remove
        scope do
          get ":type/(:id)", to: "businesses/audit_log_sinks#show_add", as: :show_add
          post ":type/add", to: "businesses/audit_log_sinks#check", constraints: lambda { |request| request.parameters[:check_button] }
          post ":type/add", to: "businesses/audit_log_sinks#upsert", as: :add
          post ":type/:id/update", to: "businesses/audit_log_sinks#check", constraints: lambda { |request| request.parameters[:check_button] }
          post ":type/:id/update", to: "businesses/audit_log_sinks#upsert", as: :update
        end
      end

      get  "/audit-log/event_settings",  to: "businesses/audit_log_event_settings#show", as: :settings_audit_log_event_settings
      get  "/audit-log/export_logs",  to: "businesses/audit_log_export_logs#show", as: :settings_audit_log_export_logs
      put  "update_event_settings",  to: "businesses/audit_log_event_settings#update", as: :settings_update_audit_log_event_settings_enabled
      get  "/audit-log/curator",  to: "businesses/audit_log_curator#index", as: :settings_audit_log_curator
      post "/audit-log/curator",  to: "businesses/audit_log_curator#update", as: :settings_audit_log_curator_update
      post "/audit-log/update_git",  to: "businesses/audit_log_curator#git_update", as: :settings_audit_log_curator_update_git
      get  "/dormant-users/exports", to: "businesses/dormant_users_export#index", as: :dormant_users_exports
      get  "/dormant-users/exports/:token", to: "businesses/dormant_users_export#show", as: :dormant_users_export
      post "/dormant-users/exports", to: "businesses/dormant_users_export#create"
      delete "/dormant-users/exports/:id", to: "businesses/dormant_users_export#destroy", as: :dormant_users_export_destroy

      get "hooks", to: "businesses/hooks#index", as: :hooks
      post "hooks", to: "businesses/hooks#create"
      get "hooks/new", to: "businesses/hooks#new", as: :new_hook
      get "hooks/:id", to: "businesses/hooks#show", as: :hook
      put "hooks/:id", to: "businesses/hooks#update"
      delete "hooks/:id", to: "businesses/hooks#destroy"

      constraints(guid: WEBHOOK_GUID_REGEX, id: WEBHOOK_REGEX, hook_id: /\d+/) do
        get  "hooks/:hook_id/deliveries",                     to: "hook_deliveries#index",     as: :hook_deliveries, context: "enterprise"
        get  "hooks/:hook_id/deliveries/:id",                 to: "hook_deliveries#show",      as: :hook_delivery, context: "enterprise"
        get  "hooks/:hook_id/deliveries/:id/payload.:format", to: "hook_deliveries#payload",   as: :delivery_payload, format: "json", context: "enterprise"
        get  "hooks/:hook_id/redeliveries",                     to: "hook_deliveries#redeliveries",     as: :hook_redeliveries, context: "enterprise"
        post "hooks/:hook_id/deliveries/:guid/redeliver",       to: "hook_deliveries#redeliver", as: :redeliver_hook_delivery, context: "enterprise"
      end

      get "retired_namespaces", to: "businesses/retired_namespaces#index", as: :settings_retired_namespaces
      delete "retired_namespaces/:id", to: "businesses/retired_namespaces#destroy", as: :settings_retired_namespaces_destroy

      get "projects", to: "businesses/projects#index", as: :settings_projects
      put "update_organization_projects_allowed", to: "businesses/organization_projects#update", as: :update_settings_organization_projects
      put "update_members_can_change_project_visibility", to: "businesses/projects_visibility#update", as: :update_members_can_change_project_visibility
      put "update_repository_projects_allowed", to: "businesses/repository_projects#update", as: :update_settings_repository_projects
      put "update_projects_automation_enabled", to: "businesses/projects_automation#update", as: :update_settings_projects_automation

      get "security", to: "businesses/security#index", as: :settings_security
      get "security_analysis", to: "businesses/security_analysis#index", as: :settings_security_analysis
      get "security_analysis/configurations/new", to: "businesses/security_analysis#new", as: :settings_security_analysis_configurations_new
      post "security_analysis/configurations", to: "businesses/security_analysis#create", as: :settings_security_analysis_configurations_create
      get "security_analysis/configurations/:id/view", to: "businesses/security_analysis#show", as: :settings_security_analysis_configuration_show
      get "security_analysis/configurations/:id/edit", to: "businesses/security_analysis#edit", as: :settings_security_analysis_configuration_edit
      put "security_analysis/configurations/:id", to: "businesses/security_analysis#update", as: :settings_security_analysis_configuration_update
      delete "security_analysis/configurations/:id", to: "businesses/security_analysis#destroy", as: :settings_security_analysis_configuration_destroy
      get "security_analysis/configurations/:id/repositories_count", to: "businesses/security_analysis#repositories_count", as: :settings_security_analysis_configuration_repositories_count
      post "security_analysis/apply_confirmation_summary", to: "businesses/security_analysis#apply_confirmation_summary", as: :settings_security_analysis_apply_confirmation_summary
      put "security_analysis/apply_configuration", to: "businesses/security_analysis#apply_configuration", as: :settings_security_analysis_apply_configuration
      put "security_analysis/resource_link", to: "businesses/security_analysis#update_resource_link", as: :settings_security_analysis_update_resource_link
      put "security_analysis/ai_detection", to: "businesses/security_analysis#update_ai_detection", as: :settings_security_analysis_update_ai_detection
      put "security_analysis/user_namespace_ghas_toggle", to: "businesses/security_analysis#user_namespace_ghas_toggle", as: :settings_security_analysis_user_namespace_toggle
      get "security_analysis/actions_runners_labels", to: "businesses/security_analysis#actions_runners_labels", as: :settings_security_analysis_actions_runners_labels

      resource :two_factor_requirement,
        as: :enterprise_two_factor_requirement,
        controller: "businesses/two_factor_requirement",
        only: %i(show update)
      get "two_factor_secure_methods_requirement", to: "businesses/two_factor_secure_methods#show", as: :two_factor_secure_methods_requirement

      resource :referrer_override,
        as: :enterprise_referrer_override,
        controller: "businesses/referrer_override",
        only: %i(update)
      resource :ssh_certificate_authority_owner_settings,
        as: :enterprise_ssh_certificate_authority_owner_settings,
        controller: "ssh_certificate_authority_owner_settings",
        only: %i(update)
      resource :ip_allowlist_enabled,
        as: :enterprise_ip_allowlist_enabled,
        controller: "ip_allowlist_enabled",
        only: %i(update)
      resource :ip_allowlist_app_access_enabled,
        as: :enterprise_ip_allowlist_app_access_enabled,
        controller: "ip_allowlist_app_access_enabled",
        only: %i(update)
      resource :ip_allowlist_user_level_enforcement_enabled,
        as: :enterprise_ip_allowlist_user_level_enforcement_enabled,
        controller: "businesses/ip_allowlist_user_level_enforcement_enabled",
        only: %i(update)
      resource :skip_idp_ip_allowlist_app_access_enabled,
        as: :enterprise_skip_idp_ip_allowlist_app_access_enabled,
        controller: "businesses/skip_idp_ip_allowlist_app_access_enabled",
        only: %i(update)
      resource :idp_ip_allowlist_for_web,
        as: :enterprise_idp_ip_allowlist_for_web,
        controller: "businesses/idp_ip_allowlist_for_web",
        only: %i(update)
      resource :ip_allowlist_configuration,
        as: :enterprise_ip_allowlist_configuration,
        controller: "businesses/ip_allowlist_configuration",
        only: %i(update)
      resource :sso_redirect_enabled,
        as: :enterprise_sso_redirect_enabled,
        controller: "businesses/sso_redirect_enabled",
        only: %i(create)
      resource :open_scim_configuration,
        as: :enterprise_open_scim_configuration,
        controller: "businesses/open_scim_configuration",
        only: %i(create)
      resource :scim_configuration,
        as: :enterprise_scim_configuration,
        controller: "businesses/scim_configuration",
        only: %i(update)

      resources :compliance_reports,
        as: :enterprise_compliance_reports,
        controller: "compliance_reports",
        param: :key,
        only: %i(show)

      resource :single_sign_on_configuration,
        as: :enterprise_single_sign_on_configuration,
        controller: "businesses/single_sign_on_configuration",
        only: %i(show)

      resource :saml_to_oidc_migration,
        as: :enterprise_saml_to_oidc_migration,
        controller: "businesses/saml_to_oidc_migration",
        only: %i(show)

      resource :saml_provider,
        as: :enterprise_saml_provider,
        controller: "businesses/saml_provider",
        only: %i(edit)

      # SAML SSO
      put "saml_provider", to: "businesses/saml_provider#update", as: :settings_saml_provider
      delete "saml_provider", to: "businesses/saml_provider#delete"
      get "saml_provider/recovery_codes", to: "businesses/saml_provider#recovery_codes", as: :settings_saml_provider_recovery_codes
      post "saml_provider/recovery_codes/download", to: "businesses/saml_provider#download_recovery_codes", as: :settings_saml_provider_download_recovery_codes
      get "saml_provider/recovery_codes/print", to: "businesses/saml_provider#print_recovery_codes", as: :settings_saml_provider_print_recovery_codes
      put "saml_provider/regenerate_recovery_codes", to: "businesses/saml_provider#regenerate_recovery_codes", as: :settings_saml_provider_regenerate_recovery_codes
      put "saml_provider/update_user_provisioning", to: "businesses/saml_provider#update_user_provisioning", as: :settings_saml_provider_update_user_provisioning
      # OIDC SSO
      post "oidc_provider", to: "businesses/oidc_provider#create", as: :settings_oidc_provider
      delete "oidc_provider", to: "businesses/oidc_provider#delete"
      get "oidc_provider/recovery_codes", to: "businesses/oidc_provider#recovery_codes", as: :settings_oidc_provider_recovery_codes
      post "oidc_provider/recovery_codes/download", to: "businesses/oidc_provider#download_recovery_codes", as: :settings_oidc_provider_download_recovery_codes
      get "oidc_provider/recovery_codes/print", to: "businesses/oidc_provider#print_recovery_codes", as: :settings_oidc_provider_print_recovery_codes
      put "oidc_provider/regenerate_recovery_codes", to: "businesses/oidc_provider#regenerate_recovery_codes", as: :settings_oidc_provider_regenerate_recovery_codes

      get    "ssh_certificate_authorities/new", to: "ssh_certificate_authorities#new",     as: :ssh_certificate_authorities_new
      post   "ssh_certificate_authorities",     to: "ssh_certificate_authorities#create",  as: :ssh_certificate_authorities
      delete "ssh_certificate_authorities/:id", to: "ssh_certificate_authorities#destroy", as: :ssh_certificate_authority
      patch  "ssh_certificate_authorities/:id/require_expiration",     to: "ssh_certificate_authority_expiration#update",  as: :ssh_certificate_authorities_require_expiration

      resources :support,
        as: :enterprise_support,
        controller: "businesses/support",
        only: %i(index)
      resources :support_entitlees,
        as: :enterprise_support_entitlees,
        controller: "businesses/support_entitlees",
        only: %i(create destroy)
      resources :support_entitlee_suggestions,
        as: :enterprise_support_entitlee_suggestions,
        controller: "businesses/support_entitlee_suggestions",
        only: %i(index)

      resources :ip_allowlist_entries,
        as: :enterprise_ip_allowlist_entries,
        only: %w(new create edit update destroy),
        controller: "ip_allowlist_entries"

      get     "installations",                           to: "businesses/installations#index",                      as: :settings_business_installations
      get     "installations/:id",                       to: "businesses/installations#show",                       as: :settings_business_installation
      put     "installations/:id/update",                to: "businesses/installations#update",                     as: :update_settings_business_installation
      delete  "installations/:id",                       to: "businesses/installations#destroy"
      get     "installations/:id/permissions/update",    to: "businesses/installations#permissions_update_request", as: :permissions_update_request_settings_business_installation
      put     "installations/:id/permissions/update",    to: "businesses/installations#update_permissions",         as: :update_permissions_settings_business_installation

      get     "domains",                                 to: "verifiable_domains#index",                            as: :settings_enterprise_domains

      if GitHub.enterprise?
        get "packages", to: "businesses/packages#show", as: :settings_packages
        put "packages", to: "businesses/packages#update_packages_settings", as: :update_settings_packages
      end

      get "announcement", to: "businesses/messages#announcement", as: :edit_announcement
      put "preview_announcement", to: "businesses/messages#preview_announcement", as: :announcement_preview
      patch "announcement", to: "businesses/messages#set_announcement", as: :set_announcement
      delete "announcement", to: "businesses/messages#destroy", as: :destroy_announcement

      get "compliance", to: "businesses/compliance#index", as: :settings_compliance

      scope "/:organization_id" do
        resource :copilot_permission_to_assign_seats, as: :enterprise_copilot_permission_to_assign_seats, controller: "businesses/copilot_permission_to_assign_seats", only: %i(update)
      end

      resource :mandatory_message,
        as: :enterprise_mandatory_message,
        controller: "businesses/mandatory_message",
        only: %i(edit update)
      resource :mandatory_message_preview,
        as: :enterprise_mandatory_message_preview,
        controller: "businesses/mandatory_message_preview",
        only: %i(create)

      resources :admin_center_options,
        as: :enterprise_admin_center_options,
        controller: "businesses/admin_center_options",
        only: %i(index update),
        param: :option_name

      scope :messages do
        get "", to: "businesses/custom_messages#index", as: :custom_messages
        get ":message", to: "businesses/custom_messages#edit", as: :custom_message
        patch "", to: "businesses/custom_messages#update"
        post "", to: "businesses/custom_messages#create"

        post ":message/preview", to: "businesses/custom_messages/preview#create", as: :custom_message_preview

        resource :announcement,
          as: :enterprise_announcement,
          controller: "businesses/custom_messages/announcement",
          only: %i(edit update)
        resource :announcement_preview,
          as: :enterprise_announcement_preview,
          controller: "businesses/custom_messages/announcement_preview",
          only: :create
        resource :announcement_dismissal,
          as: :enterprise_announcement_dismissal,
          controller: "businesses/custom_messages/announcement_dismissal",
          only: :create
      end

      scope :dotcom_connection do
        get "", to: "businesses/dotcom_connection#index", as: :admin_settings_dotcom_connection
        post "", to: "businesses/dotcom_connection#create", as: :admin_settings_create_dotcom_connection
        patch ":setting", to: "businesses/dotcom_connection#update", as: :admin_settings_update_dotcom_connection
        delete "", to: "businesses/dotcom_connection#destroy", as: :admin_settings_delete_dotcom_connection
        post "resume_dotcom_connection", to: "businesses/dotcom_connection/resumption#create", as: :admin_settings_resume_dotcom_connection
        get "complete", to: "businesses/dotcom_connection/completion#show", as: :admin_settings_complete_dotcom_connection
        get "change_complete", to: "businesses/dotcom_connection/setting_change_completion#show", as: :admin_settings_change_complete
      end

      resources :pre_receive_hooks, as: :enterprise_pre_receive_hooks,
        controller: "businesses/pre_receive_hooks", only: [:destroy]
      resources :pre_receive_hook_targets,
        as: :enterprise_pre_receive_hook_targets,
        controller: "businesses/pre_receive_hook_targets",
        only: [:new, :create, :update, :show] do
        collection do
          get "repository_search", to: "businesses/pre_receive_hook_target_repos#index"
          get "file_list", to: "businesses/pre_receive_hook_target_files#index"
        end
      end

      resources :pre_receive_environments,
        as: :enterprise_pre_receive_environments,
        controller: "businesses/pre_receive_environments",
        only: [:create, :new, :index, :show, :destroy, :update] do
        member do
          post "download", to: "businesses/pre_receive_environment_downloads#create"
          get "environment_actions", to: "businesses/pre_receive_environment_actions#index"
        end
      end

      if GitHub.sponsors_enabled?
        draw :sponsors_enterprises
      end

      get "models",                 to: "businesses/models_settings#show",            as: :settings_models
      put "models",                 to: "businesses/models_settings#update",          as: :settings_models_update_policy

      # Enterprise GitHub Apps
      post    "/installations/:id/suspended", to: "businesses/installations#suspend",   as: :suspend_settings_installation
      delete  "/installations/:id/suspended", to: "businesses/installations#unsuspend", as: :unsuspend_settings_installation

      get     "/apps/",                       to: "businesses/integrations#index",        as: :settings_apps
      get     "/apps/new",                    to: "businesses/integrations#new",          as: :new_settings_app
      post    "/apps/",                       to: "businesses/integrations#create"
      post    "/apps/preview_note",           to: "businesses/integrations#preview_note", as: :preview_permissions_note_app

      get     "/apps/:id",                    to: "businesses/integrations#show",               as: :settings_app
      get     "/apps/:id/permissions",        to: "businesses/integrations#permissions",        as: :settings_app_permissions
      get     "/apps/:id/installations",      to: "businesses/integrations#installations",      as: :settings_app_installations
      get     "/apps/:id/advanced",           to: "businesses/integrations#advanced",           as: :settings_app_advanced
      get     "/apps/:id/beta",               to: "businesses/integrations#beta_features",      as: :settings_app_beta_features
      get     "/apps/:id/copilot",            to: "businesses/integrations#copilot",            as: :settings_app_copilot
      post    "/apps/:id/sign_agreement",     to: "businesses/integrations#sign_agreement",     as: :settings_app_sign_agreement

      put     "/apps/:id",                          to: "businesses/integrations#update"
      put     "/apps/:id/permissions",              to: "businesses/integrations#update_permissions",     as: :update_settings_app_permissions
      put     "/apps/:id/beta-toggle",              to: "businesses/integrations#beta_toggle",            as: :settings_app_beta_feature_toggle
      put     "/apps/:id/copilot",                  to: "businesses/integrations#update_copilot",         as: :settings_app_update_copilot

      # The following commented out routes are intentionally commented out
      # To note that they are currently not implemented
      post    "/apps/:id/key",                      to: "businesses/integrations#generate_key",           as: :generate_key_settings_app
      delete  "/apps/:id/key/:key_id",              to: "businesses/integrations#remove_key",             as: :remove_key_settings_app
      get     "/apps/:id/keys",                     to: "businesses/integrations#keys",                   as: :list_keys_settings_app
      # put   "/apps/:id/public",                   to: "businesses/integrations#make_public",            as: :make_public_settings_app
      # put   "/apps/:id/private",                  to: "businesses/integrations#make_private",           as: :make_private_settings_app
      post    "/apps/:id/revoke_all_tokens",        to: "businesses/integrations#revoke_all_tokens",      as: :revoke_all_tokens_settings_app
      post    "/apps/:id/client_secret",            to: "businesses/integrations#generate_client_secret", as: :generate_client_secret_settings_app
      delete  "/apps/:id/client_secret/:secret_id", to: "businesses/integrations#remove_client_secret",   as: :remove_client_secret_settings_app
      delete  "/apps/:id",                          to: "businesses/integrations#destroy"
      put     "/apps/:id/transfer",                 to: "businesses/integrations#transfer",               as: :transfer_settings_app
      get     "/apps/:id/transfer_suggestions",     to: "businesses/integrations#transfer_suggestions",   as: :transfer_settings_app_suggestions

      get     "/apps/transfers/:id",                       to: "businesses/integration_transfers#show",          as: :settings_app_transfer
      delete  "/apps/transfers/:id",                       to: "businesses/integration_transfers#destroy"
      put     "/apps/transfers/:id/accept",               to: "businesses/integration_transfers#accept",        as: :accept_settings_app_transfer
    end

    if !GitHub.single_business_environment?
      resources :enterprise_installations, as: :enterprise_enterprise_installations,
        only: [:index, :create], controller: "businesses/enterprise_installations" do
        collection do
          post "user_accounts_sync", to: "businesses/enterprise_installations/user_accounts_sync#create"
          post "stats_export", to: "businesses/enterprise_installations/stats_export#create"
        end
      end

      resources :server_licenses, only: :show, module: :businesses, constraints: { id: /[\da-f]{6}(?:[\da-f]{14})?/ }

      resources :metered_server_licenses, only: [:show, :create], module: :businesses, constraints: { id: /[\da-f]{6}(?:[\da-f]{14})?/ }

      resource :enterprise_licensing, only: :show, controller: "businesses/enterprise_licensing" do
        member do
          get "download_consumed_licenses"
          get "download_active_committers"
          get "download_maximum_committers"

          # Enterprise Licensing survey
          delete "settings/survey", action: :destroy, as: :dismiss_enterprise_licensing_survey
        end
      end

      scope :enterprise_licensing, controller: "businesses/copilot_licensing_settings" do
        get "copilot", action: :index, as: :copilot_licensing_settings
      end

      scope :enterprise_licensing, controller: "businesses/copilot/standalone_enterprise_seat_management" do
        get "copilot/members/search", action: :search, as: :enterprise_members_search
        get "copilot/seat_management", action: :index, as: :team_seats
        post "copilot/seat_management", action: :create, as: :create_team_seats
        delete "copilot/seat_management", action: :destroy, as: :destroy_team_seats
        post "copilot/seat_management/download_usage", action: :download_usage, as: :download_usage
      end
    end

    # Enterprise roles
    resources :enterprise_roles, controller: "businesses/enterprise_roles", only: [:index, :new, :create, :edit, :update, :destroy] do
      collection do
        get "fgp_metadata"
      end
    end

    resources :enterprise_role_assignments, controller: "businesses/enterprise_role_assignments", only: [:index, :new, :create] do
      collection do
        delete ":actor_type/:actor_id/:role_id", to: "businesses/enterprise_role_assignments#destroy", as: :destroy
      end
    end

    resources :enterprise_role_assignment_queries, controller: "businesses/enterprise_role_assignment_queries", only: :index

    # Enterprise Teams
    resources :enterprise_teams, path: "teams", param: :team_slug, only: [:create, :destroy, :edit, :index, :update] do
      member do
        get "", to: "enterprise_team_members#index" # alias #show path to the members#index view
        resources :members, controller: "enterprise_team_members", param: :user_login, only: [:index, :create, :destroy], as: :enterprise_team_members do
          collection do
            delete "bulk_delete", to: "enterprise_team_members#destroy"
          end
        end
        resources :roles, controller: "businesses/enterprise_team_role_assignments", param: :role_id, only: [:index], as: :enterprise_team_role_assignments
        resources :organizations, controller: "businesses/enterprise_team_organization_assignments", only: [:index, :create, :destroy], as: :enterprise_team_organization_assignments do
          collection do
            delete "bulk_delete", to: "businesses/enterprise_team_organization_assignments#destroy"
          end
        end
        resources :organization_suggestions, controller: "businesses/business_team_organization_suggestions", only: [:index], as: :business_team_organization_suggestions
        resources :eligible_members, controller: "business_teams_eligible_members", only: [:index], as: :enterprise_team_eligible_members
      end
      collection do
        delete "bulk_delete", to: "enterprise_teams#destroy"
      end
    end
    get "new_team", to: "enterprise_teams#new", as: "new_enterprise_team"
    # Enterprise Teams check-name endpoint
    get "check_team_name", to: "enterprise_teams#check_name", as: :check_team_name
    # post to avoid query string length limit / pass json body for complex query
    post "organization_suggestions", to: "business_teams_eligible_org#index"
    resources :enterprise_team_member_suggestions, only: [:index]

    # Enterprise Security Manager
    resources :enterprise_security_managers, module: :"businesses/security_managers", path: :"security-managers", param: :team_slug, only: [:create, :destroy, :index] do
      collection do
        defaults format: :json do
          get :"assignment-suggestions"
          get :teams
        end
      end
    end

    # Domain verification
    resources :domains, only: [:new, :create, :destroy], controller: "verifiable_domains", as: :enterprise_domains do
      member do
        get :verification_steps, to: "verifiable_domains/verifications#show"
        put :regenerate_token, to: "verifiable_domains/tokens#update"
        put :verify, to: "verifiable_domains/verifications#update"
        put :approve, to: "verifiable_domains/approvals#update"
      end
    end

    resource :notification_restrictions,
      as: :enterprise_notification_restrictions,
      controller: "notification_restrictions",
      only: %i(show update)

    resources :organizations,
      as: :enterprise_organizations,
      only: %w(index new create destroy),
      controller: "businesses/organizations" do
      member do
        get :invite, to: "businesses/organizations/owner_invitations#new"
        post :add_owner, to: "businesses/organizations/owner_invitations#create"
        delete :cancel_invitation, to: "businesses/organizations/owner_invitations#destroy"
        get :finish, to: "businesses/organizations/completion#show"
        get :sso, to: "businesses/organizations/sso#show"
      end

      collection do
        get :suggestions, to: "filter_providers/business_organizations#index"
        get "suggestions/validate", to: "filter_providers/business_organizations#show"
      end
    end

    scope :onboarding do
      resources :organizations,
      as: :enterprise_onboarding_organizations,
      only: %w(new create),
      controller: "businesses/onboarding/organizations" do
        collection do
          get :invite
        end
      end
    end

    scope "/actions/metrics" do
      # Usage
      resource :usage, only: :show, controller: "businesses/actions_metrics/usage", as: :actions_usage_metrics_enterprise
      post :usage, action: :index, only: :index, controller: "businesses/actions_metrics/usage"
      post "usage/export", action: :export, only: :export, controller: "businesses/actions_metrics/usage"
      post "usage/export_status", action: :export_status, only: :export_status, controller: "businesses/actions_metrics/usage"
      get "usage/workflows", action: :workflows, only: :workflows, controller: "businesses/actions_metrics/usage"
      get "usage/jobs", action: :jobs, only: :jobs, controller: "businesses/actions_metrics/usage"
      get "usage/orgs", action: :orgs, only: :orgs, controller: "businesses/actions_metrics/usage"
      get "usage/runner_labels", action: :runner_labels, only: :runner_labels, controller: "businesses/actions_metrics/usage"
      post "usage/summary", action: :summary, only: :summary, controller: "businesses/actions_metrics/usage"

      # Performance
      resource :performance, only: :show, controller: "businesses/actions_metrics/performance", as: :actions_performance_metrics_enterprise
      post :performance, action: :index, only: :index, controller: "businesses/actions_metrics/performance"
      post "performance/export", action: :export, only: :export, controller: "businesses/actions_metrics/performance"
      post "performance/export_status", action: :export_status, only: :export_status, controller: "businesses/actions_metrics/performance"
      get "performance/workflows", action: :workflows, only: :workflows, controller: "businesses/actions_metrics/performance"
      get "performance/jobs", action: :jobs, only: :jobs, controller: "businesses/actions_metrics/performance"
      get "performance/orgs", action: :orgs, only: :orgs, controller: "businesses/actions_metrics/performance"
      get "performance/runner_labels", action: :runner_labels, only: :runner_labels, controller: "businesses/actions_metrics/performance"
      post "performance/summary", action: :summary, only: :summary, controller: "businesses/actions_metrics/performance"
    end

    resources :organization_transfers,
      as: :enterprise_organization_transfers,
      controller: "businesses/organization_transfers",
      only: %w(new create)
    resources :organization_transfers_enterprise_suggestions,
      as: :enterprise_organization_transfers_enterprise_suggestions,
      controller: "businesses/organization_transfers/business_suggestions",
      only: :index

    resources :organizations_settings,
      as: :enterprise_organizations_settings,
      path: "/organizations/settings",
      controller: "businesses/organizations/settings",
      only: :show,
      param: :setting

    # Business OpenID Connect SSO routes
    post "/oidc/initiate", to: "businesses/identity_management/oidc#initiate", as: :idm_oidc_initiate
    get "/oidc/recover", to: "businesses/identity_management/oidc#recover_prompt", as: :idm_oidc_recover
    post "/oidc/recover", to: "businesses/identity_management/oidc#recover"
    delete "/oidc/revoke", to: "businesses/identity_management/oidc#revoke", as: :idm_oidc_revoke

    # Business SAML SSO routes
    get "/saml/metadata", to: "businesses/identity_management/saml#metadata", as: :idm_saml_metadata
    get "/saml/enc_cert", to: "businesses/identity_management/saml#enc_cert", as: :idm_saml_enc_cert
    post "/saml/initiate", to: "businesses/identity_management/saml#initiate", as: :idm_saml_initiate
    post "/saml/consume", to: "businesses/identity_management/saml#consume", as: :idm_saml_consume
    post "/saml/continue", to: "businesses/identity_management/saml#continue", as: :idm_saml_continue
    get "/saml/recover", to: "businesses/identity_management/saml#recover_prompt", as: :idm_saml_recover
    post "/saml/recover", to: "businesses/identity_management/saml#recover"
    delete "/saml/revoke", to: "businesses/identity_management/saml#revoke", as: :idm_saml_revoke
    get  "/sso",           to: "businesses/identity_management#sso",             as: :business_idm_sso
    get  "/sso_status",    to: "businesses/identity_management#sso_status",      as: :business_idm_sso_status
    get  "/sso_modal",     to: "businesses/identity_management#sso_modal",       as: :business_idm_sso_modal
    get  "/sso_complete",  to: "businesses/identity_management#sso_complete",    as: :business_idm_sso_complete
    get  "/sso/sign_up",   to: "businesses/identity_management#sso_sign_up",     as: :business_idm_sso_sign_up

    # team synchronization endpoints
    post "/team-sync/install", to: "businesses/team_sync#install"
    get  "/team-sync/setup",          to: "businesses/team_sync#setup"
    post "/team-sync/initiate", to: "businesses/team_sync#initiate"
    get  "/team-sync/review",         to: "businesses/team_sync#review"
    post "/team-sync/approve", to: "businesses/team_sync#approve"
    delete "/team-sync/cancel", to: "businesses/team_sync#cancel"
    delete "/team-sync/disable", to: "businesses/team_sync#disable"
    put "/team-sync/update", to: "businesses/team_sync#update"

    get "/team-sync/okta-credentials/new", to: "businesses/team_sync/okta_credentials#new"
    post "/team-sync/okta-credentials", to: "businesses/team_sync/okta_credentials#create"
    get "/team-sync/okta-credentials/edit", to: "businesses/team_sync/okta_credentials#edit"
    patch "/team-sync/okta-credentials", to: "businesses/team_sync/okta_credentials#update"
    put "/team-sync/okta-credentials", to: "businesses/team_sync/okta_credentials#update"
  end

  # draw :billing_vnext
end

scope "/enterprises/:slug", as: "enterprise", controller: "businesses/org_roles" do
  get    "org_roles",               action: :index,        as: :organization_roles
  get    "org_roles/new",           action: :new,          as: :new_organization_role
  post   "org_roles",               action: :create,       as: :create_organization_role
  get    "org_roles/:id/edit",      action: :edit,         as: :edit_organization_role
  put    "org_roles/:id",           action: :update,       as: :update_organization_role
  delete "org_roles/:id",           action: :destroy,      as: :delete_organization_role
  get    "org_roles/fgp_metadata",  action: :org_roles_fgp_metadata
  get    "repo_roles/fgp_metadata", action: :repo_roles_fgp_metadata
end

resources :enterprise_user_accounts, only: [] do
  member do
    get :organizations, to: "business_user_accounts/organizations#index"
    get :enterprise_installations, to: "business_user_accounts/enterprise_installations#index"
    get :sso, to: "business_user_accounts/sso#index"
  end
end

resources :enterprise_installations, only: [:new, :destroy] do
  member do
    get "complete", to: "enterprise_installations#show"
    get "upgrade", to: "enterprise_installations#edit"
    post "upgrade_confirm", to: "enterprise_installations#update"
  end
end

post "/dotcom_connection/webhooks", to: "dotcom_connection_webhooks#create", as: :dotcom_connection_webhooks
get "enterprises/team-sync/azure-callback", to: "businesses/team_sync#azure_callback"

if GitHub.single_business_environment?
  get "/enterprise(/*route)", to: "businesses/global_business_redirect#show", as: :global_enterprise
  # EnterpriseInstallationsController#show uses a hardcoded url
  # because cloud doesn't know the enterprise account slug on the server
  # instance to formulate a full enterprise route this route will redirect
  # to the global enterprise account on the server
  get "/admin/dotcom_connection(/*path)", to: "businesses/dotcom_connection_settings_redirect#show"
end
