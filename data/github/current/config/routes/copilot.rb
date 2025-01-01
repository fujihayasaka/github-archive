# typed: strict
# frozen_string_literal: true

T.bind(self, ActionDispatch::Routing::Mapper)

DOCSET_REGEX = /(?:\w|\.|\-|%20| )+/i

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

  get "/github-copilot/signup/copilot_individual", to: redirect("/github-copilot/pro")
  get "/github-copilot/signup/billing",            to: redirect("/github-copilot/pro/signup")

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

  ## Copilot for business / enterprise purchase route
  get "github-copilot/purchase", to: "copilot/purchase/plan_purchase#new", as: :copilot_plan_purchase
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

  ## Copilot fine-tuning waitlist signup
  get   "/github-copilot/fine_tuning_waitlist_signup",           to: "copilot/fine_tuning_waitlist_signup#new",    as: :copilot_fine_tuning_waitlist_signup
  get   "/github-copilot/fine_tuning_waitlist_signup/join",      to: "copilot/fine_tuning_waitlist_signup#join",   as: :copilot_fine_tuning_waitlist_signup_join
  post  "/github-copilot/fine_tuning_waitlist_signup",           to: "copilot/fine_tuning_waitlist_signup#create", as: :copilot_fine_tuning_waitlist_signup_create
  get   "/github-copilot/customization_waitlist_signup",         to: redirect("/github-copilot/fine_tuning_waitlist_signup")
  get   "/github-copilot/customization_waitlist_signup/join",    to: redirect("/github-copilot/fine_tuning_waitlist_signup/join")

  ## Copilot Enterprise signup and upgrade
  get   "/github-copilot/enterprise_signup",                              to: "copilot/enterprise_signup#new",                    as: :copilot_enterprise_signup
  get   "/github-copilot/enterprise_signup/choose_enterprise",            to: "copilot/enterprise_signup#choose_enterprise",      as: :copilot_enterprise_signup_choose_enterprise
  get   "/github-copilot/enterprise_signup/plan_summary",                 to: "copilot/enterprise_signup#plan_summary",           as: :copilot_enterprise_signup_plan_summary
  get   "/github-copilot/enterprise_signup/payment",                      to: "copilot/enterprise_signup#payment",                as: :copilot_enterprise_signup_payment
  get   "/github-copilot/enterprise_signup/seat_management",              to: "copilot/enterprise_signup#seat_management",        as: :copilot_enterprise_signup_seat_management
  get   "/github-copilot/enterprise_signup/policy",                       to: "copilot/enterprise_signup#policy",                 as: :copilot_enterprise_signup_policy

  post  "/github-copilot/enterprise_signup/signup",                       to: "copilot/enterprise_signup#signup",                 as: :copilot_enterprise_signup_signup
  get   "/github-copilot/enterprise_signup/completion",                   to: "copilot/enterprise_signup#completion",             as: :copilot_enterprise_signup_completion

  ## Copilot Extensions waitlist signup
  get   "/github-copilot/copilot_extensions_waitlist_signup", to: redirect("/features/copilot/extensions"),    as: :copilot_extensions_waitlist_signup

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
  put  "/settings/copilot_dashboard_entry_point_enabled",   to: "settings/copilot_dashboard_entry_point_enabled#update", as: :copilot_dashboard_entry_point_enabled

  ## Copilot For Orgs Signup
  get   "/features/copilot/org_signup",             to: redirect("/github-copilot/business_signup")

  ## Copilot For Orgs Settings
  get   "/organizations/:organization_id/settings/copilot/enable",     to: "orgs/copilot_settings/enable#index",        as: :settings_org_copilot_enable
  get   "/organizations/:organization_id/settings/copilot/chat_settings",     to: "orgs/copilot_settings/chat_settings#index",        as: :settings_org_copilot_chat_settings
  get   "/organizations/:organization_id/settings/copilot/chat_settings/knowledge_bases",     to: "orgs/copilot_settings/chat_settings#list",        as: :settings_org_copilot_chat_settings_list
  get   "/organizations/:organization_id/settings/copilot/chat_settings/new",     to: "orgs/copilot_settings/chat_settings#new",        as: :settings_org_copilot_chat_settings_new
  get   "/organizations/:organization_id/settings/copilot/chat_settings/knowledge_bases/:id",     to: "orgs/copilot_settings/chat_settings#show",        as: :settings_org_copilot_chat_settings_show
  get   "/organizations/:organization_id/settings/copilot/chat_settings/:id/edit",     to: "orgs/copilot_settings/chat_settings#edit",        as: :settings_org_copilot_chat_settings_edit
  post  "/organizations/:organization_id/settings/copilot/chat_settings",     to: "orgs/copilot_settings/chat_settings#create",        as: :settings_org_copilot_chat_settings_create
  put   "/organizations/:organization_id/settings/copilot/chat_settings/:id",     to: "orgs/copilot_settings/chat_settings#update",        as: :settings_org_copilot_chat_settings_update
  delete   "/organizations/:organization_id/settings/copilot/chat_settings/:id",     to: "orgs/copilot_settings/chat_settings#destroy",        as: :settings_org_copilot_chat_settings_destroy
  post  "/organizations/:organization_id/settings/copilot/chat_settings/check_name",     to: "orgs/copilot_settings/chat_settings#check_name",        as: :settings_org_copilot_chat_settings_check_name
  get   "/organizations/:organization_id/settings/copilot/policies",   to: "orgs/copilot_settings/policies#index",      as: :settings_org_copilot_policies
  get   "/organizations/:organization_id/settings/copilot/models",   to: "orgs/copilot_settings/policies#models",      as: :settings_org_copilot_models
  put   "/organizations/:organization_id/settings/copilot/policies",   to: "orgs/copilot_settings/policies#update",      as: :settings_org_copilot_policies_update
  get   "/organizations/:organization_id/settings/copilot/coding_agent",   to: "orgs/copilot_settings/swe_agent#index",      as: :settings_org_copilot_swe_agent
  put   "/organizations/:organization_id/settings/copilot/coding_agent/repositories", to: "orgs/copilot_settings/swe_agent#update_repos",      as: :settings_org_copilot_swe_agent_update_repos
  get   "/organizations/:organization_id/settings/copilot/csv_exports",   to: "orgs/copilot_settings/csv_exports#index",      as: :settings_org_copilot_csv_exports
  post  "/organizations/:organization_id/settings/copilot/csv_exports",   to: "orgs/copilot_settings/csv_exports#create",      as: :settings_org_copilot_csv_exports_generate
  scope "/organizations/:organization_id/settings/copilot", module: "orgs/copilot_settings", as: :settings_org_copilot do
    resource :custom_instructions, only: [:show, :create]
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
  put "/organizations/:organization_id/settings/copilot/add_seat",   to: "orgs/copilot_settings/seat_management#create",      as: :add_org_copilot_seat_management
  put "/organizations/:organization_id/settings/copilot/add_seats",   to: "orgs/copilot_settings/seat_management#create_users",      as: :add_org_copilot_seats_management
  put "/organizations/:organization_id/settings/copilot/add_team",   to: "orgs/copilot_settings/seat_management#create_team",      as: :add_org_team_copilot_seat_management
  put "/organizations/:organization_id/settings/copilot/add_teams",   to: "orgs/copilot_settings/seat_management#create_teams",      as: :put_org_invitation_copilot_seat_management
  put "/organizations/:organization_id/settings/copilot/send_invitation",   to: "orgs/copilot_settings/seat_management#send_invitation",      as: :add_org_teams_copilot_seat_management
  put "/organizations/:organization_id/settings/copilot/send_invitations",   to: "orgs/copilot_settings/seat_management#send_invitations",      as: :org_copilot_send_invitations
  delete "/organizations/:organization_id/settings/copilot/remove_seat",   to: "orgs/copilot_settings/seat_management#destroy",      as: :delete_org_copilot_seat_management
  delete "/organizations/:organization_id/settings/copilot/remove_team_seat",   to: "orgs/copilot_settings/seat_management#destroy_team",      as: :delete_org_team_copilot_seat_management
  delete "/organizations/:organization_id/settings/copilot/remove_invitation",   to: "orgs/copilot_settings/seat_management#destroy_invitation",      as: :delete_org_invitation_copilot_seat_management

  get "/organizations/:organization_id/settings/copilot/members",   to: "orgs/copilot_settings/member_search#index",      as: :settings_org_copilot_members

  get "/organizations/:organization_id/settings/copilot/users/suggestions",   to: "orgs/copilot_settings/seat_management#suggestions",      as: :settings_org_copilot_user_suggestions
  get "/organizations/:organization_id/settings/copilot/teams/suggestions",   to: "orgs/copilot_settings/seat_management#team_suggestions",      as: :settings_org_copilot_team_suggestions
  post  "/organizations/:organization_id/settings/copilot/add_users_csv",   to: "orgs/copilot_settings/seat_management#save_csv_users",      as: :org_copilot_add_users_csv
  post  "/organizations/:organization_id/settings/copilot/confirm_add_users_csv",   to: "orgs/copilot_settings/seat_management#confirm_csv_users",      as: :org_copilot_confirm_users_csv
  post  "/organizations/:organization_id/settings/copilot/generate_csv",   to: "orgs/copilot_settings/seat_management#generate_csv",      as: :org_copilot_generate_csv
  post "/organizations/:organization_id/settings/copilot/filter_seat_management", to: "orgs/copilot_settings/seat_management#filter", as: :org_copilot_seat_management_filter
  post "/organizations/:organization_id/settings/copilot/filter_all_seat_management", to: "orgs/copilot_settings/seat_management#all_filter", as: :org_copilot_seat_management_all_filter
  post "/organizations/:organization_id/settings/copilot/search_seat_management", to: "orgs/copilot_settings/seat_management#search", as: :org_copilot_seat_management_search
  post "/organizations/:organization_id/settings/copilot/search_all_seat_management", to: "orgs/copilot_settings/seat_management#all_search", as: :org_copilot_seat_management_all_search
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
  get "/copilot/loops", to: "copilot/immersive#show", as: :copilot_immersive_loops
  get "/copilot/loop/share", to: "copilot/immersive#show", as: :copilot_immersive_loop_share
  get "/copilot/l/:loop_id", to: "copilot/immersive#show", as: :copilot_immersive_loop
  get "/copilot/agents", to: "copilot/immersive/agent_sessions#show", as: :copilot_agents_list
  scope "/github-copilot", module: "copilot" do
    get "/chat", to: "chat#show", as: :copilot_chat
    namespace :chat, as: :copilot_chat do
      resources :attachments, only: [:show]
      resource :agents, only: :show
      get "custom_copilots/:owner/:number", to: "copilot_spaces#show"
      resources :custom_copilots, controller: "copilot_spaces", only: [:index, :show]
      get "custom_copilots_owners", to: "copilot_spaces_owners#index"
      resource :token, only: :create
      resource :entitlement, only: :show
      resources :repositories, only: :show
      get "repositories/:user_id/:repository", to: "repositories#show", constraints: { user_id: USERID_REGEX, repository: REPO_REGEX }
      get "implicit-context/:user_id/:repository/:url", to: "context#show", constraints: { url: /\S+/, user_id: USERID_REGEX, repository: REPO_REGEX }
      resources :feedback, only: :create do
        collection do
          get :"interview-survey"
        end
      end
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

    namespace :docs, as: :copilot_for_docs do
      resources :docsets, only: [:index]
      get "/docsets/kb_indexed_repos", to: "docsets#kb_indexed_repos"
    end
  end
  get "/copilot/r/:user_id/:repository", to: "copilot/immersive#show", as: :copilot_immersive_repo, constraints: { user_id: USERID_REGEX, repository: REPO_REGEX }
  get "/copilot/d/:docset_name", to: "copilot/immersive#show", as: :copilot_immersive_docset, constraints: { docset_name: DOCSET_REGEX }
  post "/copilot/immersive/markdown", to: "copilot/immersive/markdown#index", as: :copilot_immersive_markdown
  get "/copilot/immersive/figma-link", to: "copilot/immersive/figma_link#show", as: :copilot_immersive_figma
  post "/copilot/completions/nl-search", to: "copilot/nl_github_search_completions#create", as: :nl_github_search
  post "/copilot/loops/loops_execution", to: "copilot/loops/loops_execution#create", as: :loops_execution
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

  # copilot spaces paths (use the same controller as immersive)
  get "/copilot/spaces", to: "copilot/immersive#show", as: :copilot_spaces_list
  get "/copilot/spaces/:space_id", to: "copilot/immersive#show", as: :copilot_spaces_show
  get "/copilot/spaces/:owner/:number", to: "copilot/immersive#show", as: :copilot_spaces_show_by_number
  get "/copilot/spaces/:space_id/edit", to: "copilot/immersive#show", as: :copilot_spaces_edit
  get "/copilot/spaces/:owner/:number/edit", to: "copilot/immersive#show", as: :copilot_spaces_edit_by_number

  # legacy immersive path redirects
  get "/github-copilot", to: redirect("/copilot")
  get "/github-copilot/c/:thread_id", to: redirect("/copilot/c/%{thread_id}")
  get "/github-copilot/r/:user_id/:repository", to: redirect("/copilot/r/%{user_id}/%{repository}")
  get "/github-copilot/d/:docset_name", to: redirect("/copilot/d/%{docset_name}")

  ## Repo-scoped Copilot Routes
  scope "/:user_id/:repository", constraints: { user_id: USERID_REGEX, repository: REPO_REGEX }, as: :repo do
    put "/copilot/completions/feedback/session/:session_id", to: "copilot/repository_completion_feedback#update", as: :completion_feedback_session
    put "/copilot/completions/feedback/:job_id", to: "copilot/repository_completion_feedback#update", as: :completion_feedback
    post "/copilot/completions/diff_summary", to: "copilot/diff_summary_repository_completions#create",
      as: :diff_summary_completions

    get "/settings/copilot/coding_agent", to: "repos/copilot_settings/swe_agent#index", as: :repo_settings_copilot_swe_agent
    put "/settings/copilot/coding_agent", to: "repos/copilot_settings/swe_agent#update", as: :repo_settings_copilot_swe_agent_update

    get "/settings/copilot/content_exclusion", to: "repos/copilot_settings/content_exclusion#show", as: :repo_settings_copilot_content_exclusion
    put "/settings/copilot/content_exclusion", to: "repos/copilot_settings/content_exclusion#update", as: :repo_settings_copilot_content_exclusion_update
    get "/settings/copilot/code_review",       to: "edit_repositories/copilot_code_guidelines#index", as: :repo_settings_copilot_code_review

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

    # Agent Sessions
    delete "/pull/:pull_number/agent-sessions/:session_id", to: "repos/agent_sessions#destroy", as: :agent_session_destroy
    get "/pull/:pull_number/agent-sessions", to: "repos/agent_sessions#index", as: :agent_sessions
    get "/pull/:pull_number/agent-sessions/:session_id", to: "repos/agent_sessions#show", as: :agent_session
    post "/pull/:pull_number/agent-sessions/token", to: "repos/agent_sessions_token#create", as: :create_agent_session_token

    # Spark Workbench Cloudspaces
    post "/copilot/workbench/cloud_environment", to: "copilot/workbench/cloud_environment#create",  as: :copilot_workbench_cloud_environment_create
    post "/copilot/workbench/cloud_environment/:identifier", to: "copilot/workbench/cloud_environment#update",  as: :copilot_workbench_cloud_environment_update, id: /\d+/, format: false, defaults: { format: :json }
    get "/copilot/workbench/cloud_environment/:identifier", to: "copilot/workbench/cloud_environment#show",  as: :copilot_workbench_cloud_environment_show, id: /\d+/, format: false, defaults: { format: :json }

    ## Copilot Code Review
    get "/copilot/review/access", to: "copilot/code_review#has_access", as: :has_access_copilot_code_review
    post "/copilot/review/pull/:pull", to: "copilot/code_review#new", as: :new_copilot_code_review
    post "/pull/:pull/code_review_feedback", to: "copilot/code_review_feedback#create", as: :copilot_code_review_feedback
    scope "/copilot", module: "copilot" do
      scope "/pull/:pull" do
        resource :code_review_feedback, only: [:create], controller: :code_review_feedback
      end
    end
  end

  ## Copilot product feedback
  post "/github-copilot/feedback", to: "copilot/feedback#create", as: :copilot_feedback

  put "/github-copilot/preferences", to: "copilot/preferences#update", as: :copilot_preferences

  ## Custom Copilots
  post "/custom_copilots", to: "copilot/copilot_spaces#create", as: :create_custom_copilot_deprecated
  put "/custom_copilots/:id", to: "copilot/copilot_spaces#update", as: :update_custom_copilots
  delete "/custom_copilots/:id", to: "copilot/copilot_spaces#destroy", as: :destroy_custom_copilots

  ## Personal instructions
  post "/copilot/personal_instructions", to: "copilot/personal_instructions#create", as: :create_personal_instructions

  # Copilot issues
  post "/copilot_issues/bulk_create", to: "copilot_issues/bulk_create#create", format: :json, as: :copilot_issues_bulk_create
end
