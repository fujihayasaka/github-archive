# typed: strict
# frozen_string_literal: true

T.bind(self, ActionDispatch::Routing::Mapper)

DOCSET_REGEX = /(?:\w|\.|\-|%20| )+/i
TASK_ID_REGEX = /(?!pull\z)[^\/]+/

# Rails routing constraint used on /copilot to conditionally render a new
# experience for unauthenticated visitors.
module CopilotChatLoggedOutConstraint
  sig { params(request: ActionDispatch::Request).returns(T::Boolean) }
  def self.matches?(request)
    CopilotPLG.domain.logged_out_copilot_chat_enabled?(request)
  end
end

# Rails routing constraint used on /copilot/share/:thread_id to conditionally render
# the logged out view for bots.
module CopilotSharedChatLoggedOutConstraint
  sig { params(request: ActionDispatch::Request).returns(T::Boolean) }
  def self.matches?(request)
    CopilotPLG.domain.logged_out_copilot_shared_chat_enabled?(request)
  end
end

# Restrict enterprise (GHES) access to all copilot routes
unless GitHub.enterprise?
  # TEMPORARY PAGES FEATURE FLAGGED
  get "/github-copilot/quotas/:user_id", to: "copilot/quotas#show", as: :copilot_quota
  put "/github-copilot/quotas/:user_id", to: "copilot/quotas#update", as: :copilot_quota_update

  ### These are all copilot related routes
  get   "/github-copilot/signup/plans",               to: "copilot/signup#choose_plan_type",    as: :copilot_signup_choose_plan_type,          defaults: { business_only: false }
  get   "/github-copilot/business_signup/plans",      to: "copilot/signup#choose_plan_type",    as: :copilot_signup_business_choose_plan_type, defaults: { business_only: true }

  ## Copilot Individual signup routes
  get   "/github-copilot/signup",                     to: "copilot/signup#new",                 as: :copilot_signup
  get   "/github-copilot/free_signup",                to: "copilot/signup#free_signup",         as: :copilot_free_signup
  post  "/github-copilot/signup/subscribe_free_user", to: "copilot/signup#subscribe_free_user", as: :copilot_signup_subscribe_free_user
  post  "/github-copilot/signup/subscribe_limited_user", to: "copilot/signup#subscribe_limited_user", as: :copilot_signup_subscribe_limited_user
  post  "/github-copilot/signup/subscribe",           to: "copilot/signup#subscribe",           as: :copilot_signup_subscribe
  get   "/github-copilot/signup/success",             to: "copilot/signup#success",             as: :copilot_signup_success
  put   "/github-copilot/signup/settings",            to: "copilot/signup#settings",            as: :copilot_signup_settings
  post  "/github-copilot/signup/upgrade_trial",       to: "copilot/signup#upgrade_trial",       as: :copilot_signup_upgrade_trial

  get "/github-copilot/signup/copilot_individual", to: redirect { |_params, request|
    query = request.query_string.present? ? "?#{request.query_string}" : ""
    "/github-copilot/pro#{query}"
  }
  get "/github-copilot/signup/billing", to: redirect { |_params, request|
    query = request.query_string.present? ? "?#{request.query_string}" : ""
    "/github-copilot/pro/signup#{query}"
  }

  # Upgrade redirect route — redirects to the next tier's signup based on the user's current plan
  get "/github-copilot/upgrade", to: "copilot/upgrade#show", as: :copilot_upgrade

  # Pro signup routes
  get  "/github-copilot/pro",        to: "copilot/pro_signup#index",  as: :copilot_pro_signup
  get  "/github-copilot/pro/signup", to: "copilot/pro_signup#new",    as: :copilot_pro_signup_new
  post "/github-copilot/pro/signup", to: "copilot/pro_signup#create", as: :copilot_pro_signup_create
  put  "/github-copilot/pro/signup", to: "copilot/pro_signup#update", as: :copilot_pro_signup_update

  # Pro Plus signup routes
  get  "/github-copilot/pro-plus",           to: "copilot/pro_plus_signup#index",     as: :copilot_pro_plus_signup
  get  "/github-copilot/pro-plus/signup",    to: "copilot/pro_plus_signup#new",       as: :copilot_pro_plus_signup_new
  post "/github-copilot/pro-plus/signup",    to: "copilot/pro_plus_signup#create",    as: :copilot_pro_plus_signup_create
  put  "/github-copilot/pro-plus/signup",    to: "copilot/pro_plus_signup#update",    as: :copilot_pro_plus_signup_update
  post "/github-copilot/pro-plus/downgrade", to: "copilot/pro_plus_signup#downgrade", as: :copilot_pro_plus_downgrade

  # Max signup routes
  get  "/github-copilot/max",            to: "copilot/max_signup#index",        as: :copilot_max_signup
  get  "/github-copilot/max/signup",     to: "copilot/max_signup#new",          as: :copilot_max_signup_new
  post "/github-copilot/max/signup",     to: "copilot/max_signup#create",       as: :copilot_max_signup_create
  put  "/github-copilot/max/signup",     to: "copilot/max_signup#update",       as: :copilot_max_signup_update
  post "/github-copilot/max/downgrade",  to: "copilot/max_signup#downgrade",    as: :copilot_max_downgrade

  # Pay to continue (CFI pay-as-you-go) routes
  get  "/github-copilot/pay-to-continue", to: "copilot/pay_to_continue#new",    as: :copilot_pay_to_continue
  post "/github-copilot/pay-to-continue", to: "copilot/pay_to_continue#create", as: :copilot_pay_to_continue_create

  ## Copilot for business / enterprise purchase route
  get "github-copilot/purchase", to: "copilot/purchase/plan_purchase#new", as: :copilot_plan_purchase
  get "github-copilot/purchase/accounts",
    to: "copilot/purchase/plan_purchase#index",
    as: :copilot_plan_purchase_accounts,
    defaults: { format: :html_fragment },
    constraints: ->(req) { req.format == Mime[:html_fragment] }
  put "github-copilot/purchase", to: "copilot/purchase/plan_purchase#update", as: :copilot_plan_purchase_update

  ## Copilot for Business First Run Experience
  get   "/github-copilot/business_signup",                              to: "copilot/business_signup#new",                    as: :copilot_business_signup
  get   "/github-copilot/business_signup/choose_business_type",         to: "copilot/business_signup#choose_business_type",   as: :copilot_business_signup_choose_business_type
  get   "/github-copilot/business_signup/choose_enterprise",            to: "copilot/business_signup#choose_enterprise",      as: :copilot_business_signup_choose_enterprise
  get   "/github-copilot/business_signup/choose_organization",          to: "copilot/business_signup#choose_organization",    as: :copilot_business_signup_choose_organization
  get   "/github-copilot/business_signup/enterprise/payment",           to: "copilot/business_signup#enterprise_payment",     as: :copilot_business_signup_enterprise_payment
  get   "/github-copilot/business_signup/enterprise/policy",            to: "copilot/business_signup#enterprise_policy",      as: :copilot_business_signup_enterprise_policy
  get   "/github-copilot/business_signup/enterprise/seat_management",   to: "copilot/business_signup#enterprise_seat_management",      as: :copilot_business_signup_enterprise_seat_management
  get   "/github-copilot/business_signup/organization/payment",         to: "copilot/business_signup#organization_payment",   as: :copilot_business_signup_organization_payment
  get   "/github-copilot/business_signup/organization/policy",          to: "copilot/business_signup#organization_policy",    as: :copilot_business_signup_organization_policy
  get   "/github-copilot/business_signup/organization/seat_management", to: "copilot/business_signup#organization_seat_management",    as: :copilot_business_signup_organization_seat_management
  post  "/github-copilot/business_signup/organization/signup",          to: "copilot/business_signup#organization_signup",    as: :copilot_business_signup_organization_signup
  get   "/github-copilot/business_signup/completion",                   to: "copilot/business_signup#signup_completion",      as: :copilot_business_signup_completion

  ## Copilot Enterprise signup and upgrade
  get   "/github-copilot/enterprise_signup",                              to: "copilot/enterprise_signup#new",                    as: :copilot_enterprise_signup
  get   "/github-copilot/enterprise_signup/choose_enterprise",            to: "copilot/enterprise_signup#choose_enterprise",      as: :copilot_enterprise_signup_choose_enterprise
  get   "/github-copilot/enterprise_signup/plan_summary",                 to: "copilot/enterprise_signup#plan_summary",           as: :copilot_enterprise_signup_plan_summary
  get   "/github-copilot/enterprise_signup/payment",                      to: "copilot/enterprise_signup#payment",                as: :copilot_enterprise_signup_payment
  get   "/github-copilot/enterprise_signup/seat_management",              to: "copilot/enterprise_signup#seat_management",        as: :copilot_enterprise_signup_seat_management
  get   "/github-copilot/enterprise_signup/policy",                       to: "copilot/enterprise_signup#policy",                 as: :copilot_enterprise_signup_policy

  post  "/github-copilot/enterprise_signup/signup",                       to: "copilot/enterprise_signup#signup",                 as: :copilot_enterprise_signup_signup
  get   "/github-copilot/enterprise_signup/completion",                   to: "copilot/enterprise_signup#completion",             as: :copilot_enterprise_signup_completion

  ## Copilot Next Edit Suggestions waitlist signup
  get   "/github-copilot/copilot_next_edit_suggestions_waitlist_signup",           to: "copilot/next_edit_suggestions_waitlist_signup#new",    as: :copilot_next_edit_suggestions_waitlist_signup
  get   "/github-copilot/copilot_next_edit_suggestions_waitlist_signup/join",      to: "copilot/next_edit_suggestions_waitlist_signup#join",   as: :copilot_next_edit_suggestions_waitlist_signup_join
  post  "/github-copilot/copilot_next_edit_suggestions_waitlist_signup",           to: "copilot/next_edit_suggestions_waitlist_signup#create", as: :copilot_next_edit_suggestions_waitlist_signup_create
  get   "/github-copilot/next_edit_suggestions_signup",         to: redirect("/github-copilot/copilot_next_edit_suggestions_waitlist_signup")
  get   "/github-copilot/next_edit_suggestions_signup/join",    to: redirect("/github-copilot/copilot_next_edit_suggestions_waitlist_signup/join")

  ## Old o1 waitlist signup
  get   "/o1-waitlist-signup",           to: redirect("#{GitHub.url}/features/copilot"),    as: :copilot_o1_waitlist_signup

  ## Copilot settings
  get  "/settings/copilot",                                 to: "settings/copilot/features#index",                       as: :copilot_settings
  put  "/settings/copilot",                                 to: "settings/copilot/features#update",                      as: :copilot_save_settings
  get  "/settings/copilot/features",                        to: "settings/copilot/features#index",                       as: :copilot_features
  post "/settings/copilot/show_copilot",                    to: "settings/copilot/features#show_copilot",                as: :copilot_show_copilot
  get  "/settings/copilot/coding_agent",                    to: "settings/copilot/swe_agent#index",                      as: :copilot_swe_agent
  put  "/settings/copilot/coding_agent/repositories",       to: "settings/copilot/swe_agent#update_repos",               as: :copilot_swe_agent_update_repos
  put  "/settings/copilot/coding_agent/toggle_third_party_agents_enablement", to: "settings/copilot/swe_agent#toggle_third_party_agents_enablement", as: :copilot_swe_agent_toggle_third_party_enablement
  get  "/settings/copilot/memory",                          to: "settings/copilot/memory#index",                         as: :copilot_memory
  delete "/settings/copilot/memory",                        to: "settings/copilot/memory#destroy",                       as: :copilot_memory_delete
  put  "/settings/copilot_dashboard_entry_point_enabled",   to: "settings/copilot_dashboard_entry_point_enabled#update", as: :copilot_dashboard_entry_point_enabled

  ## Copilot For Orgs Signup
  get   "/features/copilot/org_signup",             to: redirect("/github-copilot/business_signup")

  ## Copilot For Orgs Settings
  get   "/organizations/:organization_id/settings/copilot",            to: "orgs/copilot_settings#index",               as: :settings_org_copilot
  get   "/organizations/:organization_id/settings/copilot/enable",     to: "orgs/copilot_settings/enable#index",        as: :settings_org_copilot_enable
  get   "/organizations/:organization_id/settings/copilot/policies",   to: "orgs/copilot_settings/policies#index",      as: :settings_org_copilot_policies
  get   "/organizations/:organization_id/settings/copilot/models",   to: "orgs/copilot_settings/policies#models",      as: :settings_org_copilot_models
  put   "/organizations/:organization_id/settings/copilot/policies",   to: "orgs/copilot_settings/policies#update",      as: :settings_org_copilot_policies_update
  put   "/organizations/:organization_id/settings/copilot/policies/mcp_registry_url", to: "orgs/copilot_settings/policies#create_or_update_mcp_registry_url", as: :settings_org_copilot_mcp_registry_url_create_or_update
  get   "/organizations/:organization_id/settings/copilot/code_review", to: "orgs/copilot_settings/code_review_approvals#index", as: :settings_org_copilot_code_review
  put   "/organizations/:organization_id/settings/copilot/code_review", to: "orgs/copilot_settings/code_review_approvals#update", as: :settings_org_copilot_code_review_update
  get   "/organizations/:organization_id/settings/copilot/code_review_approvals/repository_items", to: "orgs/copilot_settings/code_review_approval_repository_items#index", as: :settings_org_copilot_code_review_approval_repository_items
  get   "/organizations/:organization_id/settings/copilot/coding_agent",   to: "orgs/copilot_settings/swe_agent#index",      as: :settings_org_copilot_swe_agent
  put   "/organizations/:organization_id/settings/copilot/coding_agent/repositories", to: "orgs/copilot_settings/swe_agent#update_repos",      as: :settings_org_copilot_swe_agent_update_repos
  put   "/organizations/:organization_id/settings/copilot/coding_agent/toggle_third_party_agents_enablement", to: "orgs/copilot_settings/swe_agent#toggle_third_party_agents_enablement", as: :settings_org_copilot_swe_agent_toggle_third_party_agents_enablement, defaults: { format: :json }
  get   "/organizations/:organization_id/settings/copilot/coding_agent/allowlist", to: "orgs/copilot_settings/swe_agent#firewall_allowlist_edit", as: :settings_org_copilot_swe_agent_allowlist
  put   "/organizations/:organization_id/settings/copilot/coding_agent/firewall", to: "orgs/copilot_settings/swe_agent#update_firewall_configuration", as: :settings_org_copilot_swe_agent_update_firewall, defaults: { format: :json }
  put   "/organizations/:organization_id/settings/copilot/coding_agent/runner_settings", to: "orgs/copilot_settings/swe_agent#update_runner_settings", as: :settings_org_copilot_swe_agent_update_runner_settings, defaults: { format: :json }
  put   "/organizations/:organization_id/settings/copilot/coding_agent/automations_disabled", to: "orgs/copilot_settings/swe_agent#update_automations_disabled", as: :settings_org_copilot_swe_agent_update_automations_disabled, defaults: { format: :json }
  put   "/organizations/:organization_id/settings/copilot/coding_agent/trigger_actor_policy", to: "orgs/copilot_settings/swe_agent#update_trigger_actor_policy", as: :settings_org_copilot_swe_agent_update_trigger_actor_policy, defaults: { format: :json }
  # Runner type settings (standalone page, behind ccr_runner_type_org_settings FF)
  get   "/organizations/:organization_id/settings/copilot/runner_type", to: "orgs/copilot_settings/runner_type#index", as: :settings_org_copilot_runner_type
  put   "/organizations/:organization_id/settings/copilot/runner_type", to: "orgs/copilot_settings/runner_type#update", as: :settings_org_copilot_runner_type_update, defaults: { format: :json }
  get   "/organizations/:organization_id/settings/copilot/csv_exports",   to: "orgs/copilot_settings/csv_exports#index",      as: :settings_org_copilot_csv_exports
  post  "/organizations/:organization_id/settings/copilot/csv_exports",   to: "orgs/copilot_settings/csv_exports#create",      as: :settings_org_copilot_csv_exports_generate
  scope "/organizations/:organization_id/settings/copilot", module: "orgs/copilot_settings", as: :settings_org_copilot do
    resource :custom_instructions, only: [:show, :create]
    resource :memory_export, path: "memory_exports", only: [:show, :create], controller: :memory_exports do
      get :download
    end
    resource :memory_delete, path: "memory_deletes", only: [:show, :create], controller: :memory_deletes
  end

  ## Custom models org settings
  get    "/organizations/:organization_id/settings/copilot/custom_models", to: "orgs/copilot_settings/custom_models#index", as: :settings_org_copilot_custom_models
  get    "/organizations/:organization_id/settings/copilot/custom_model/new", to: "orgs/copilot_settings/custom_models#new", as: :settings_org_copilot_custom_models_new
  post   "/organizations/:organization_id/settings/copilot/custom_model/new", to: "orgs/copilot_settings/custom_models#create", as: :settings_org_copilot_custom_models_create
  get    "/organizations/:organization_id/settings/copilot/custom_model/:pipeline_id/edit", to: "orgs/copilot_settings/custom_models#edit", as: :settings_org_copilot_custom_models_edit
  delete "/organizations/:organization_id/settings/copilot/custom_model/:pipeline_id", to: "orgs/copilot_settings/custom_models#destroy", as: :settings_org_copilot_custom_models_destroy
  delete "/organizations/:organization_id/settings/copilot/custom_model/:pipeline_id/cancel", to: "orgs/copilot_settings/custom_models#cancel", as: :settings_org_copilot_custom_models_cancel
  get    "/organizations/:organization_id/settings/copilot/custom_model/:pipeline_id/repositories", to: "orgs/copilot_settings/custom_model_pipeline_repositories#index", as: :settings_org_copilot_custom_model_pipeline_repositories
  get    "/organizations/:organization_id/settings/copilot/custom_model/:pipeline_id/repositories/search", to: "orgs/copilot_settings/custom_model_pipeline_repositories#search", as: :settings_org_copilot_custom_model_pipeline_repositories_search

  get    "/organizations/:organization_id/custom_models_ga_ui", to: "orgs/copilot_settings/custom_models_ga_ui#index", as: :custom_models_ga_ui
  get    "/organizations/:organization_id/custom_models_ga_ui/new", to: "orgs/copilot_settings/custom_models_ga_ui#new", as: :custom_models_ga_ui_new
  get    "/organizations/:organization_id/custom_models_ga_ui/assessing", to: "orgs/copilot_settings/custom_models_ga_ui#assessing", as: :custom_models_ga_ui_assessing
  get    "/organizations/:organization_id/custom_models_ga_ui/assessment", to: "orgs/copilot_settings/custom_models_ga_ui#assessment", as: :custom_models_ga_ui_assessment
  get    "/organizations/:organization_id/custom_models_ga_ui/training", to: "orgs/copilot_settings/custom_models_ga_ui#training", as: :custom_models_ga_ui_training

  ## Custom model trainings
  get    "/organizations/:organization_id/settings/copilot/custom_model/training/:pipeline_id", to: "orgs/copilot_settings/custom_model_trainings#show", as: :settings_org_copilot_custom_model_trainings_show

  get   "/organizations/:organization_id/settings/copilot/seat_management",   to: "orgs/copilot_settings/seat_management#index",      as: :settings_org_copilot_seat_management
  post "/organizations/:organization_id/settings/copilot/seats/create", to: "orgs/copilot_settings/seat_management#create_seats", as: :add_org_copilot_seats
  put "/organizations/:organization_id/settings/copilot/add_seats",   to: "orgs/copilot_settings/seat_management#create_users",      as: :add_org_copilot_seats_management
  put "/organizations/:organization_id/settings/copilot/add_team",   to: "orgs/copilot_settings/team_seats#create",      as: :add_org_team_copilot_seat_management
  put "/organizations/:organization_id/settings/copilot/add_teams",   to: "orgs/copilot_settings/seat_management#create_teams",      as: :put_org_invitation_copilot_seat_management
  put "/organizations/:organization_id/settings/copilot/send_invitation",   to: "orgs/copilot_settings/invitations#create",      as: :add_org_teams_copilot_seat_management
  put "/organizations/:organization_id/settings/copilot/send_invitations",   to: "orgs/copilot_settings/seat_management#send_invitations",      as: :org_copilot_send_invitations
  delete "/organizations/:organization_id/settings/copilot/remove_seat",   to: "orgs/copilot_settings/seat_management#destroy",      as: :delete_org_copilot_seat_management
  delete "/organizations/:organization_id/settings/copilot/remove_team_seat",   to: "orgs/copilot_settings/team_seats#destroy",      as: :delete_org_team_copilot_seat_management
  delete "/organizations/:organization_id/settings/copilot/remove_invitation",   to: "orgs/copilot_settings/invitations#destroy",      as: :delete_org_invitation_copilot_seat_management

  get "/organizations/:organization_id/settings/copilot/members",   to: "orgs/copilot_settings/member_search#index",      as: :settings_org_copilot_members

  get "/organizations/:organization_id/settings/copilot/users/suggestions",   to: "orgs/copilot_settings/seat_management#suggestions",      as: :settings_org_copilot_user_suggestions
  get "/organizations/:organization_id/settings/copilot/teams/suggestions",   to: "orgs/copilot_settings/seat_management#team_suggestions",      as: :settings_org_copilot_team_suggestions
  post  "/organizations/:organization_id/settings/copilot/add_users_csv",   to: "orgs/copilot_settings/seat_management#save_csv_users",      as: :org_copilot_add_users_csv
  post  "/organizations/:organization_id/settings/copilot/confirm_add_users_csv",   to: "orgs/copilot_settings/seat_management#confirm_csv_users",      as: :org_copilot_confirm_users_csv
  post  "/organizations/:organization_id/settings/copilot/generate_csv",   to: "orgs/copilot_settings/seat_management#generate_csv",      as: :org_copilot_generate_csv
  post  "/organizations/:organization_id/settings/copilot/generate_activity_csv",   to: "orgs/copilot_settings/seat_management#generate_activity_csv",      as: :org_copilot_generate_activity_csv
  post "/organizations/:organization_id/settings/copilot/seat_management_permissions", to: "orgs/copilot_settings/seat_management#update_copilot_seat_permissions", as: :org_copilot_seat_permissions
  post "/organizations/:organization_id/settings/copilot/seat_management_permissions_json", to: "orgs/copilot_settings/seat_management#update_copilot_seat_permissions_json", as: :org_copilot_seat_permissions_json
  post "/organizations/:organization_id/settings/copilot/seat_management/seats", to: "orgs/copilot_settings/seat_management#seats", as: :copilot_seat_management_seats
  post "/organizations/:organization_id/settings/copilot/seat_management_bulk_update", to: "orgs/copilot_settings/seat_management#bulk_update", as: :copilot_seat_management_bulk_update

  get "/organizations/:organization_id/settings/copilot/content_exclusion", to: "orgs/copilot_settings/content_exclusion#show", as: :org_settings_copilot_content_exclusion
  put "/organizations/:organization_id/settings/copilot/content_exclusion", to: "orgs/copilot_settings/content_exclusion#update", as: :org_settings_copilot_content_exclusion_update

  ## Snippy v2 code referencing in dotcom
  scope "/github-copilot", module: "copilot" do
    get "/code_referencing", to: "code_referencing#show", as: :copilot_code_referencing
    resources :code_referencing, only: [:create, :new]
  end

  ## Conversational Copilot in dotcom
  get "/copilot", to: "copilot/immersive#logged_out_show", as: :copilot_immersive_logged_out, constraints: CopilotChatLoggedOutConstraint
  get "/copilot", to: "copilot/immersive#show", as: :copilot_immersive
  get "/copilot/share/:thread_id", to: "copilot/immersive#logged_out_shared_view", as: :copilot_immersive_shared_thread_logged_out, constraints: CopilotSharedChatLoggedOutConstraint
  get "/copilot/share/:thread_id", to: "copilot/immersive#show", as: :copilot_immersive_shared_thread, defaults: { shared_thread: true }
  get "/copilot/c/:thread_id", to: "copilot/immersive#show", as: :copilot_immersive_thread
  # TODO: Deprecate /copilot/agents in favor of /copilot/tasks once clients have been updated
  get "/copilot/agents", to: "copilot/agents#show", as: :copilot_agent_tasks_show
  get "/copilot/agents/access_denied", to: "copilot/immersive/agent_tasks#user_access_denied", as: :copilot_agent_tasks_access_denied
  get "/copilot/tasks", to: "copilot/immersive/agent_tasks#show", as: :copilot_agent_tasks
  get "/copilot/tasks/pull/:global_id", to: "copilot/immersive/agent_task#show", as: :copilot_agent_task
  get "/copilot/tasks/:task_id", to: "copilot/immersive/unscoped_task#show", as: :copilot_unscoped_task, constraints: { task_id: TASK_ID_REGEX }

  # Intent Detection POC
  get "/copilot/t/:user_id/:repository/:task_id", to: "copilot/immersive/task#show",
    constraints: { user_id: USERID_REGEX, repository: REPO_REGEX },
    as: :copilot_immersive_task

  scope "/github-copilot", module: "copilot" do
    get "/chat", to: "chat#show", as: :copilot_chat
    namespace :chat, as: :copilot_chat do
      resource :deferred_payload, only: :show
      resources :attachments, only: [:show]
      get "custom_copilots/:owner/:number", to: "copilot_spaces#show"
      get "custom_copilots/search", to: "copilot_spaces#search"
      get "custom_copilots/count", to: "copilot_spaces#count"
      resources :custom_copilots, controller: "copilot_spaces", only: [:index, :show]
      get "custom_copilots_owners", to: "copilot_spaces_owners#index"
      resource :token, only: :create
      resource :entitlement, only: :show
      resources :repositories, only: :show
      get "repositories/:user_id/:repository", to: "repositories#show", constraints: { user_id: USERID_REGEX, repository: REPO_REGEX }
      get "repositories_search", to: "repositories_search#index"
      get "file_contents/:id/:ref/*file_path", to: "file_contents#show", constraints: { id: /\d+/ }, format: false
      get "file_contents_nwo/:owner_login/:name/:ref/*file_path", to: "file_contents#show", constraints: { owner_login: REPO_REGEX, name: REPO_REGEX }, format: false # REPO_REGEX is inclusive of user logins
      get "file_contents_nwo/:owner_login/:name/*file_path", to: "file_contents#show", constraints: { owner_login: REPO_REGEX, name: REPO_REGEX }, format: false # REPO_REGEX is inclusive of user logins
      get "implicit-context/:user_id/:repository/:url", to: "context#show", constraints: { url: /\S+/, user_id: USERID_REGEX, repository: REPO_REGEX }
      resources :feedback, only: :create
      resources :reference_details, only: :create
      resources :threads, only: [:index, :show, :create, :destroy] do
        resources :messages, only: [:index, :create]
        scope module: :threads do
          resource :name, only: [:update]
          resource :clear, only: [:update]
        end
      end
    end
    resource :pull_request_review_banners, path: "/:user_id/:repository/pulls/review-banner",
      only: [:show, :destroy, :create], user_id: USERID_REGEX, repository: REPO_REGEX,
      as: :copilot_pull_request_review_banner
  end
  get "/copilot/r/:user_id/:repository", to: "copilot/immersive#show", as: :copilot_immersive_repo, constraints: { user_id: USERID_REGEX, repository: REPO_REGEX }
  post "/copilot/immersive/markdown", to: "copilot/immersive/markdown#index", as: :copilot_immersive_markdown
  get "/copilot/immersive/figma-link", to: "copilot/immersive/figma_link#show", as: :copilot_immersive_figma
  post "/copilot/completions/nl-search", to: "copilot/nl_github_search_completions#create", as: :nl_github_search
  post "/copilot/prompt", to: "copilot/immersive#authenticate_prompt", as: :copilot_authenticate_prompt

  # spaces CRUD uses its own controller, only meant to be called via ajax
  post "/copilot/spaces", to: "copilot/copilot_spaces#create", as: :create_custom_copilot
  post "/copilot/spaces/resource_sizes", to: "copilot/copilot_spaces#resource_sizes", as: :copilot_space_resource_sizes
  put "/copilot/spaces/:owner/:number", to: "copilot/copilot_spaces#update", as: :update_copilot_space_by_number
  delete "/copilot/spaces/:owner/:number", to: "copilot/copilot_spaces#destroy", as: :destroy_copilot_space_by_number
  post "/copilot/spaces/validate_url_resources", to: "copilot/copilot_spaces#validate_url_resources", as: :validate_copilot_space_url_resources
  post "/copilot/spaces/:owner/:number/stars", to: "copilot/starred_copilot_spaces#create", as: :starred_custom_copilot
  delete "/copilot/spaces/:owner/:number/stars", to: "copilot/starred_copilot_spaces#destroy", as: :unstarred_custom_copilot
  get "/copilot/spaces/:owner/:number/settings/visibility", to: "copilot/copilot_spaces/visibility_settings#show", as: :copilot_spaces_visibility_settings
  scope path: "/copilot/spaces/:owner/:number", as: :copilot_spaces do
    get "permissions", to: "copilot/copilot_spaces/permissions#index"
    get "suggested_collaborators", to: "copilot/copilot_spaces/suggested_collaborators#index"
    get "menu_actions", to: "copilot/copilot_spaces/menu_actions#index"
    resource :permissions, only: [:create, :destroy, :update], controller: "copilot/copilot_spaces/permissions"
  end

  # copilot spaces paths (use the same controller as immersive)
  get "/copilot/spaces", to: "copilot/immersive#show", as: :copilot_spaces_list
  get "/copilot/spaces/new", to: "copilot/immersive#show", as: :copilot_spaces_show
  get "/copilot/spaces/:owner/:number", to: "copilot/immersive#show", as: :copilot_spaces_show_by_number
  get "/copilot/spaces/:owner/:number/edit", to: "copilot/immersive#show", as: :copilot_spaces_edit_by_number

  # coffe trace view
  get "/copilot/trace/:thread_id", to: "copilot/copilot_trace_viewer#show", as: :copilot_trace_viewer

  # legacy immersive path redirects
  get "/github-copilot", to: redirect("/copilot")
  get "/github-copilot/c/:thread_id", to: redirect("/copilot/c/%{thread_id}")
  get "/github-copilot/r/:user_id/:repository", to: redirect("/copilot/r/%{user_id}/%{repository}")

  # Copilot coding agent
  get "/copilot/agent-sessions/alive-channels", to: "copilot_sessions/alive_channels#show", as: :copilot_sessions_alive_channels
  get "/copilot/agent-sessions/pull-requests", to: "copilot_sessions/pull_requests#index", as: :copilot_sessions_pull_requests
  get "/copilot/agent-sessions/pull-requests/:pull_request_id/agent-mentions", to: "copilot_sessions/pull_requests/agent_mentions#index", as: :copilot_sessions_pull_request_agent_mentions
  get "/copilot/agent-sessions/repositories", to: "copilot_sessions/repositories#index", as: :copilot_sessions_repositories
  get "/copilot/agent-sessions/users", to: "copilot_sessions/users#index", as: :copilot_sessions_users
  get "/copilot/agent-sessions/agents/:agent_id", to: "copilot_sessions/agent_info#show", as: :copilot_sessions_agent_info
  get "/copilot/agent-sessions/:user_id/:repository/agents", to: "copilot_sessions/agent_info#index", as: :copilot_sessions_agents_list, constraints: { user_id: USERID_REGEX, repository: REPO_REGEX }
  post "/copilot/agent-sessions/:user_id/:repository/agents/:agent_id/authorize", to: "copilot_sessions/agent_info#authorize", as: :copilot_sessions_agent_authorize, constraints: { user_id: USERID_REGEX, repository: REPO_REGEX }
  post "/copilot/agent-sessions/token", to: "repos/agents/agent_sessions_token#create", as: :create_agent_session_token
  scope "/copilot/agent-sessions", module: "copilot_sessions", as: :copilot_sessions do
    resource :quota_snapshot, only: :show, path: "quota-snapshot", controller: "agent_quota_snapshots"
  end

  ## Repo-scoped Copilot Routes
  scope "/:user_id/:repository", constraints: { user_id: USERID_REGEX, repository: REPO_REGEX }, as: :repo do
    put "/copilot/completions/feedback/session/:session_id", to: "copilot/repository_completion_feedback#update", as: :completion_feedback_session
    put "/copilot/completions/feedback/:job_id", to: "copilot/repository_completion_feedback#update", as: :completion_feedback
    post "/copilot/completions/diff_summary", to: "copilot/diff_summary_repository_completions#create",
      as: :diff_summary_completions

    # MCP servers settings (standalone page, behind ccr_mcp_repo_settings FF)
    get "/settings/copilot/mcp", to: "repos/copilot_settings/mcp#index", as: :repo_settings_copilot_mcp
    put "/settings/copilot/mcp", to: "repos/copilot_settings/mcp#update", as: :repo_settings_copilot_mcp_update

    get "/settings/copilot/coding_agent", to: "repos/copilot_settings/swe_agent#index", as: :repo_settings_copilot_swe_agent
    get "/settings/copilot/coding_agent/allowlist", to: "repos/copilot_settings/swe_agent#firewall_allowlist_edit", as: :repo_settings_copilot_swe_agent_allowlist
    put "/settings/copilot/coding_agent/mcp", to: "repos/copilot_settings/swe_agent#update_mcp_configuration", as: :repo_settings_copilot_swe_agent_update
    put "/settings/copilot/coding_agent/firewall", to: "repos/copilot_settings/swe_agent#update_firewall_configuration", as: :repo_settings_copilot_swe_agent_update_firewall, defaults: { format: :json }
    put "/settings/copilot/coding_agent/use_codeql", to: "repos/copilot_settings/swe_agent#update_use_codeql", as: :repo_settings_copilot_swe_agent_update_use_codeql, defaults: { format: :json }
    put "/settings/copilot/coding_agent/use_ccr", to: "repos/copilot_settings/swe_agent#update_use_ccr", as: :repo_settings_copilot_swe_agent_update_use_ccr, defaults: { format: :json }
    put "/settings/copilot/coding_agent/use_secret_scanning", to: "repos/copilot_settings/swe_agent#update_use_secret_scanning", as: :repo_settings_copilot_swe_agent_update_use_secret_scanning, defaults: { format: :json }
    put "/settings/copilot/coding_agent/use_dependency_vuln_checks", to: "repos/copilot_settings/swe_agent#update_use_dependency_vuln_checks", as: :repo_settings_copilot_swe_agent_update_use_dependency_vuln_checks, defaults: { format: :json }
    put "/settings/copilot/coding_agent/require_workflow_approval", to: "repos/copilot_settings/swe_agent#update_require_workflow_approval", as: :repo_settings_copilot_swe_agent_update_require_workflow_approval, defaults: { format: :json }
    put "/settings/copilot/coding_agent/automations_disabled", to: "repos/copilot_settings/swe_agent#update_automations_disabled", as: :repo_settings_copilot_swe_agent_update_automations_disabled, defaults: { format: :json }
    put "/settings/copilot/coding_agent/trigger_actor_policy", to: "repos/copilot_settings/swe_agent#update_trigger_actor_policy", as: :repo_settings_copilot_swe_agent_update_trigger_actor_policy, defaults: { format: :json }
    put "/settings/copilot/coding_agent/memory_disabled", to: "repos/copilot_settings/swe_agent#update_memory_disabled", as: :repo_settings_copilot_swe_agent_update_memory_disabled, defaults: { format: :json }
    # Repository-level Copilot Memory settings
    get "/settings/copilot/memory", to: "repos/copilot_settings/memory#index", as: :repo_settings_copilot_memory
    put "/settings/copilot/memory/disabled", to: "repos/copilot_settings/memory#update_memory_disabled", as: :repo_settings_copilot_memory_update_disabled, defaults: { format: :json }
    delete "/settings/copilot/memory", to: "repos/copilot_settings/memory#destroy", as: :repo_settings_copilot_memory_delete

    get "/settings/copilot/content_exclusion", to: "repos/copilot_settings/content_exclusion#show", as: :repo_settings_copilot_content_exclusion
    put "/settings/copilot/content_exclusion", to: "repos/copilot_settings/content_exclusion#update", as: :repo_settings_copilot_content_exclusion_update
    get "/settings/copilot/code_review",       to: "edit_repositories/copilot_code_review_settings#index", as: :repo_settings_copilot_code_review
    put "/settings/copilot/code_review/qualified_approval", to: "copilot/code_review_repository_qualified_approval_settings#update", as: :code_review_repository_qualified_approval_settings
    post "/settings/copilot/code_review/create_ruleset", to: "edit_repositories/default_copilot_code_review_rulesets#create", as: :create_copilot_ruleset_repo_repo_settings_copilot_code_review

    get "/pull/:id/edit", to: "workspace_editor/index#show", as: :workspace_editor, id: /\d+/, format: false, defaults: { format: :html }
    get "/pull/:id/edit/new", to: "workspace_editor/index#show", as: :workspace_editor_new, id: /\d+/, format: false, defaults: { format: :html }
    get "/pull/:id/edit/file/*path", to: "workspace_editor/index#show", as: :workspace_editor_edit, id: /\d+/, format: false, defaults: { format: :html }
    post "/pull/:id/edit/commit_changes", to: "workspace_editor/commit_changes#create",  as: :workspace_editor_commit, id: /\d+/
    post "/pull/:id/workspace_editor/cloud_environment", to: "workspace_editor/cloud_environment#create",  as: :workspace_editor_cloud_environment_create, id: /\d+/, format: false, defaults: { format: :json }
    get "/pull/:id/workspace_editor/cloud_environment/permissions_check", to: "workspace_editor/cloud_environment#permissions_check",  as: :workspace_editor_cloud_environment_permissions_check, format: false, defaults: { format: :json }
    get "/pull/:id/workspace_editor/cloud_environment/:identifier", to: "workspace_editor/cloud_environment#show",  as: :workspace_editor_show, id: /\d+/, format: false, defaults: { format: :json }
    get "/pull/:id/diff", to: "workspace_editor/diff#show",                              as: :workspace_editor_diff, id: /\d+/, format: false
    get "/pull/:id/workspace_editor/suggestions", to: "workspace_editor/suggestions#index",          as: :workspace_editor_suggestions, id: /\d+/, format: false
    get "/pull/:id/workspace_editor/suggestions/:pull_request_review_comment_id", to: "workspace_editor/suggestions#show", as: :workspace_editor_suggestion_show, id: /\d+/, format: false
    get "/pull/:id/edit/overview", to: "workspace_editor/overview#show",                 as: :workspace_editor_overview, id: /\d+/, format: false
    get "/pull/:id/workspace_editor/files/:commit_oid/*path", to: "workspace_editor/files#show",                 as: :workspace_editor_file, id: /\d+/, format: false

    post "/pull/:id/coding_agent_feedback", to: "copilot/swe_agent/feedback#create", as: :swe_agent_feedback, id: /\d+/, format: false

    # Coding Agent Models
    get "/copilot/coding_agent/models", to: "copilot/swe_agent/models#index", as: :coding_agent_models, format: false, defaults: { format: :json }

    # Copilot Agents
    get "/agents", to: "repos/agents/tasks#index", as: :agents
    get "/agents/automations", to: "repos/agents/automations#index", as: :automations
    get "/agents/automations/new", to: "repos/agents/automations#new", as: :new_automation
    get "/agents/automations/:id", to: "repos/agents/automations#show", as: :automation
    get "/agents/automations/:id/edit", to: "repos/agents/automations#edit", as: :edit_automation
    get "/agents/pull/:pull_number", to: "repos/agents/pull_tasks#show", as: :agents_task
    get "/tasks/:task_id", to: "repos/agents/tasks#task", as: :task
    get "/agents/pull/:pull_number/diff", to: "repos/agents/tasks#pull_diff", as: :agents_task_pull_diff
    get "/tasks/:task_id/diff", to: "repos/agents/tasks#task_diff", as: :task_diff

    # Sessions Redirect
    get "/sessions/:session_id", to: "repos/sessions#show", as: :session

    # Agent Sessions
    post "/agent-sessions", to: "repos/agents/agent_sessions#create", as: :create_agent_session
    get "/pull/:pull_number/agent-sessions/:session_id", to: "repos/agents/agent_sessions#show", as: :agent_session

    # Spark Workbench Cloudspaces
    post "/copilot/workbench/cloud_environment", to: "copilot/workbench/cloud_environment#create",  as: :copilot_workbench_cloud_environment_create
    post "/copilot/workbench/cloud_environment/:identifier", to: "copilot/workbench/cloud_environment#update",  as: :copilot_workbench_cloud_environment_update, id: /\d+/, format: false, defaults: { format: :json }
    get "/copilot/workbench/cloud_environment/:identifier", to: "copilot/workbench/cloud_environment#show",  as: :copilot_workbench_cloud_environment_show, id: /\d+/, format: false, defaults: { format: :json }
    post "/copilot/workbench/cloud_environment/:identifier/create_snapshot", to: "copilot/workbench/cloud_environment#create_snapshot",  as: :copilot_workbench_cloud_environment_create_snapshot, id: /\d+/, format: false, defaults: { format: :json }

    # Copilot Compute Codespaces
    post "/copilot/compute/codespace", to: "copilot/compute/codespace#create", as: :copilot_compute_codespace_create, format: false, defaults: { format: :json }
    get "/copilot/compute/codespace/:identifier", to: "copilot/compute/codespace#show", as: :copilot_compute_codespace_show, format: false, defaults: { format: :json }
    post "/copilot/compute/codespace/:identifier/start", to: "copilot/compute/codespace#start", as: :copilot_compute_codespace_start, format: false, defaults: { format: :json }

    ## Copilot Code Review
    get "/copilot/review/access", to: "copilot/code_review#has_access", as: :has_access_copilot_code_review
    post "/copilot/review/pull/:pull", to: "copilot/code_review#new", as: :new_copilot_code_review
    post "/pull/:pull/code_review_feedback", to: "copilot/code_review_feedback#create", as: :copilot_code_review_feedback
    get "/pull/:pull/code_review_findings", to: "copilot/code_review_findings#index", as: :copilot_code_review_findings_index
    post "/pull/:pull/code_review_findings/fix", to: "copilot/code_review_findings#fix", as: :copilot_code_review_findings_fix
    post "/pull/:pull/ci_analysis/apply_suggestions", to: "copilot/ci_analysis#apply_suggestions", as: :copilot_ci_analysis_apply_suggestions
    get "/pull/:pull/page_data/ci_findings", to: "copilot/ci_analysis#show", as: :copilot_ci_analysis_show
    post "/pull/:pull/code_review_findings/feedback", to: "copilot/code_review_findings#feedback", as: :copilot_code_review_findings_feedback
    post "/pull/:pull/code_review_findings/ignore", to: "copilot/code_review_findings#ignore", as: :copilot_code_review_findings_ignore
    delete "/pull/:pull/code_review_findings/ignore", to: "copilot/code_review_findings#unignore", as: :copilot_code_review_findings_unignore
    post "/pull/:pull/code_review_fix_with_copilot", to: "copilot/code_review_fix_with_copilot#create", as: :copilot_code_review_fix_with_copilot
    scope "/copilot", module: "copilot" do
      scope "/pull/:pull" do
        resource :code_review_feedback, only: [:create], controller: :code_review_feedback
      end
    end
  end

  ## Copilot product feedback
  post "/github-copilot/feedback", to: "copilot/feedback#create", as: :copilot_feedback

  put "/github-copilot/preferences", to: "copilot/preferences#update", as: :copilot_preferences

  ## Copilot Spaces using the old custom_copilots naming
  post "/custom_copilots", to: "copilot/copilot_spaces#create", as: :create_custom_copilot_deprecated

  ## Personal instructions
  post "/copilot/personal_instructions", to: "copilot/personal_instructions#create", as: :create_personal_instructions

  # Copilot issues
  post "/copilot_issues/bulk_create", to: "copilot_issues/bulk_create#create", format: :json, as: :copilot_issues_bulk_create

  # Copilot BYOK (bring your own key)
  scope(
    "/organizations/:organization_id/settings/copilot",
    constraints: { organization_id: USERID_REGEX },
  ) do
    scope module: :orgs, as: :orgs do
      scope module: :copilot_settings, as: :copilot_settings do
        resources :byok_custom_keys, only: [:destroy, :update], path: "custom-keys"

        put "custom-models", to: "byok_custom_models_batch_updates#update", as: :byok_custom_models_batch_updates

        post "custom-models/:provider/models", to: "byok_provider_models#create",
          as: :byok_custom_models_fetch_provider_models
      end

      scope module: :copilot_settings, as: :copilot_settings do
        resources :byok_custom_models, only: [:index, :create, :update], path: "custom-models"
      end
    end
  end

  get "/copilot/app/launch", to: "copilot/app#index", as: :copilot_app_launch
  get "/copilot/xcode/install", to: "copilot/xcode/install#index", as: :copilot_xcode_install
end
