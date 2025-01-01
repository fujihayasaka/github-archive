# frozen_string_literal: true

GitHub::Application.routes.draw do
  if Rails.env.test?
    ::TestRoutes = ActionDispatch::Routing::RouteSet.new unless defined?(::TestRoutes)
    mount ::TestRoutes, at: "/"
  end

  if Rails.env.development? && !ENV["FASTDEV"] && !ENV["PRELOAD"] && !ENV["SKIP_LOOKBOOK"]
    mount Lookbook::Engine, at: "/lookbook"
  elsif Rails.env.development? && ENV["SKIP_LOOKBOOK"]
    get "/lookbook", to: "internal/missing_lookbook#index"
  end

  if Rails.env.development? || Rails.env.test?
    scope "/component_preview_actions", module: :component_preview_actions do
      resources :select_panel_items, only: [:index]
    end
  end

  if Rails.env.development?
    # Provides no-op /github/collect endpoint for local development
    constraints({ host: "collector.github.localhost" }) do
      post "/github/collect", to: "collect#create"
    end
  end

  REPO_REGEX = /(?:\w|\.|\-)+/i unless defined?(REPO_REGEX)
  # Copied from User::LOGIN_REGEX, but modified slightly because:
  # "Regexp anchor characters are not allowed in routing requirements"
  #
  # This supports "_" for legacy superfans with logins that still contain "_".
  # It also supports old usernames with leading dashes like -andrew-
  USERID_REGEX = /-?[a-z0-9][a-z0-9\-\_]*/i unless defined?(USERID_REGEX)

  STRIPE_ACCOUNT_ID_REGEX = /acct_[a-z0-9]*/i unless defined?(STRIPE_ACCOUNT_ID_REGEX)

  # This supports int or shaish Gist IDs
  GISTID_REGEX   = /\d+|[a-f0-9]{32}|[a-f0-9]{20}?/ unless defined?(GISTID_REGEX)

  GIT_OID_REGEX = /[a-f0-9]{40}/ unless defined?(GIT_OID_REGEX)

  BRANCH_REGEX = /[^\/]+(\/[^\/]+)?/ unless defined?(BRANCH_REGEX)

  APP_FILTER_REGEX = %r{(app/)?[^/]+}i unless defined?(APP_FILTER_REGEX)

  # Allow periods and dashes in package names, but also allow % for URL-encoded characters
  PACKAGE_DEPENDENCY_REGEX = /(?:([-:.%\w]+)|(@[-:.\/%\w]+))/i unless defined?(PACKAGE_DEPENDENCY_REGEX)

  WEBHOOK_GUID_REGEX = /\h{8}-\h{4}-\h{4}-\h{4}-\h{12}/ unless defined?(WEBHOOK_GUID_REGEX)
  WEBHOOK_REGEX = /\d+/ unless defined?(WEBHOOK_REGEX)

  # GitHub fully supports IPv4 and IPv6. Routes don't allow anchors, so we must
  # convert the existing regex to a string, remove the anchors, and then convert
  # it back to a regex.
  IP_REGEX = Regexp.union(
    Regexp.new(Resolv::IPv4::Regex.to_s.gsub(/(\\A)|(\\z)/, "")),
    Regexp.new(Resolv::IPv6::Regex.to_s.gsub(/(\\A)|(\\z)/, "")),
  ) unless defined?(IP_REGEX)

  # This is used to indicate that the '.' in the Iv1 Client ID is not
  # a separator for the ID and format as it would be parsed in a typical
  # Rails route (e.g. Iv1.abc12 => { client_id: "Iv1", format: "abc12 })
  #
  # By passing this regex to the route, we can ensure that the entire
  # client ID is passed to the controller as a single parameter.
  # (e.g. Iv1.abc12 => { client_id: "Iv1.abc12" })
  AUTHORIZATION_KEY_REGEX = /[a-f0-9]{20}|Iv1\.[a-f0-9]{16}|Iv2[a-zA-Z0-9]{17}|Ov2[a-zA-Z0-9]{17}/ unless defined?(AUTHORIZATION_KEY_REGEX)

  # Codespace names are built off the owner's login and the repository name. The
  # repo regex is inclusive of the user regex, so we can just use that.
  CODESPACE_REGEX = REPO_REGEX unless defined?(CODESPACE_REGEX)
  # Modified from Codespaces::UserSecret to accommodate lack of support for anchor characters
  CODESPACE_SECRET_NAME_REGEX = /[a-zA-Z0-9_]+/ unless defined?(CODESPACE_SECRET_NAME_REGEX)

  # This constraint will redirect all notifications routes to the relevant notifications v2 routes
  NOTIFICATIONS_V2_REDIRECT_CONSTRAINT = lambda { |_request| true } unless defined?(NOTIFICATIONS_V2_REDIRECT_CONSTRAINT)

  # DEPRECATED: PLEASE DO NOT COPY THIS PATTERN
  # Routing constraints should never make DB calls, routes may be matched
  # significantly earlier in a request than expected and may be evaluated
  # multiple times. DO NOT USE THIS.
  # Part of https://github.com/github/i2c-backlog/issues/673
  # This constraint can be added to an org memex route such that
  # it will only be matched if the numbered memex exists.
  org_memex_exists_constraint = -> (request) do
    start_time = GitHub::Dogstats.monotonic_time

    org = Organization.select("id").find_by_login(request.params[:org])
    return false unless org
    org.memex_projects.where(number: request.params[:memex_number]).exists?
  ensure
    elapsed = GitHub::Dogstats.duration(start_time)
    GitHub.dogstats.distribution(
      "memex.routing_constraint.matches",
      elapsed
    )
  end

  # DEPRECATED: PLEASE DO NOT COPY THIS PATTERN
  # Routing constraints should never make DB calls, routes may be matched
  # significantly earlier in a request than expected and may be evaluated
  # multiple times. DO NOT USE THIS.
  # This constraint can be added to an user memex route such that
  # it will only be matched if the numbered memex exists.
  user_memex_exists_constraint = -> (request) do
    user = User.find_by_login(request.params[:user_id])
    return false unless user
    user.memex_projects.where(number: request.params[:memex_number]).exists?
  end

  # Add route for OpenID Connect callback
  post "/auth/oidc/callback", to: "businesses/identity_management/oidc#callback", as: :oidc_auth

  ##
  # Status
  get "/status", to: "status_lolrails#index"

  # Temporary performance test endpoint
  get "/Ω", to: "performancetest#show"

  # User Hovercards
  # Deprecated route slated to be removed
  get "/hovercards", to: "hovercards/users#show_legacy"

  ##
  # Comment Edit History
  resources :user_content_edits, only: [:show, :destroy]
  get "/user_content_edits/show_edit_history/:comment_id", to: "user_content_edits#show_edit_history", as: :show_comment_edit_history
  get "/user_content_edits/show_edit_history_log/:comment_id", to: "user_content_edits#show_edit_history_log", as: :show_comment_edit_history_log

  # Workers
  get "/assets-cdn/worker/:path", to: "web_worker#serve_worker_from_origin", format: [:js], as: :web_worker

  # Live updates
  get "/_alive", to: "web_sockets#show", as: :alive_web_socket
  post "/_alive", to: "web_sockets#create"

  #Internal Feedback Issue module: :internal
  scope module: "internal" do
    post "/internal_feedback_issue", to: "feedback#create", as: :internal_feedback
    get  "/search_interal_feedback_repos", to: "feedback#search", as: :internal_repo_search
  end

  # User setting to toggle diff view options
  post "/users/diffview",    to: "diff_view#update_view_preference", as: :diffview

  get "/llama2-onnx/signup", to: "sdn_llama_signups#new", as: :llama2_show
  post "/llama2-onnx/request-access", to: "sdn_llama_signups#create", as: :llama2_request_access
  post "/llama2-onnx/update-billing", to: "sdn_llama_signups#update", as: :llama2_update_billing

  ##############################################################################
  # NOTE: Only routes that should work on BOTH GitHub and Gist should appear
  # before this line
  ##############################################################################

  # Gists
  if GitHub.gist3_domain?
    constraints({ host: /#{GitHub.gist3_host_name}\.?/ }) do
      draw :gist
    end
  else
    scope "/gist" do
      draw :gist
    end
  end

  ##
  # OctoCaptcha
  if GitHub.funcaptcha_enabled?
    constraints(host: /#{GitHub.urls.octocaptcha_host_name}/) do
      get "/", to: "octocaptcha#index"
      get "/test", to: "octocaptcha#test"
      get "/octocaptcha_test", to: "octocaptcha#octocaptcha_test"
      post "/v1/verify", to: "octocaptcha#verify_v1", defaults: { format: :json }
      match "/:path", to: "octocaptcha#not_found", constraints: { path: /.*/ }, via: [:get, :post, :put, :delete, :patch]
    end
  end

  # Chatops endpoints
  if GitHub.chatops_endpoint_enabled?
    draw :chatops
  end

  ##
  # Legacy (rofl)
  get "/~:path", to: "tilde_redirect#index", constraints: { path: /.*/ }

  ##
  # Bounces
  get "/:contributing",       to: redirect("/about/jobs"), contributing: /contributing(.md)?/i
  get "/launch",              to: redirect("/search")

  ##
  # Head
  get "/manifest.json", to: "head#manifest"

  ##
  # Gist aliases
  get "/gist", to: redirect(GitHub.gist_url)
  get "/gists", to: redirect(GitHub.gist_url)

  # Non-Enterprise Bounces
  #
  # Before adding/removing things from this (and other GitHub.enterprise?)
  # block(s) check ensure that they are also moved to the global_denylist
  # in config/initializers/denylist.rb
  unless GitHub.enterprise?
    get "/c",                    to: redirect("/contact")
    get "/github-community",     to: redirect("/orgs/community/discussions")
    get "/press",                to: redirect("/about/press")
    get "/mac",                  to: redirect("https://mac.github.com")
    get "/windows",              to: redirect("https://windows.github.com")
    get "/pages",                to: redirect("https://pages.github.com")
    get "/training/online",      to: redirect("https://training.github.com/classes/")
    get "/training/events",      to: redirect("https://training.github.com/schedule/")
    get "/training/free",        to: redirect("https://training.github.com/kit/")
    get "/training/:other",      to: redirect("https://training.github.com/")
    get "/training",             to: redirect("https://training.github.com/")
    get "/site/privacy",         to: redirect("#{GitHub.privacy_url}"), as: :site_privacy
    get "/site/terms",           to: redirect("#{GitHub.terms_url}"), as: :site_terms
    get "/terms",                to: redirect("#{GitHub.help_url}/site-policy/github-terms/github-terms-of-service")
    get "/tos",                  to: redirect("#{GitHub.help_url}/site-policy/github-terms/github-terms-of-service")
    get "/site/corporate-terms", to: redirect("#{GitHub.help_url}/site-policy/github-terms/github-corporate-terms-of-service"), as: :site_corp_terms
    get "/site/education-terms", to: redirect("https://education.github.com/schools/terms/"), as: :site_education_terms
    get "/site/esa",             to: redirect("#{GitHub.help_url}/en/articles/github-enterprise-subscription-agreement"), as: :site_esa
    get "/supplemental-products-and-features", to: redirect("#{GitHub.help_url}/github/site-policy/github-additional-product-terms")
    get "/mirrors",              to: redirect("#{GitHub.help_url}/en/github/getting-started-with-github/finding-ways-to-contribute-to-open-source-on-github")
    get "/forrester",            to: redirect("https://resources.github.com/forrester/")
    get "/site-policy",          to: redirect("#{GitHub.help_url}/en/github/site-policy")
    get "/subprocessors",        to: redirect("#{GitHub.help_url}/github/site-policy/github-subprocessors-and-cookies")
    get "/github-subprocessors-list", to: redirect("#{GitHub.help_url}/github/site-policy/github-subprocessors-and-cookies")
    get "/additional-products-and-features-terms", to: redirect("#{GitHub.help_url}/github/site-policy/github-additional-product-terms")
    get "/",                     to: redirect("/about/developer-policy"), constraints: { subdomain: "policy" }
  end

  get "/site/bounce", to: "bounce#index"
  scope controller: "bounce", action: "index" do
    get "/repositories/new", as: nil, format: false, defaults: { to: "/new" }
  end

  # Retired Features
  get "/inbox/sent", to: redirect("/410")

  # Changed password reset URL
  get "/sessions/forgot_password", to: redirect("/password_reset")

  ##
  # Marketing pages aka Site
  draw :site

  # In product messaging routes
  post "/track-nudge-impression", to: "in_product_messaging_impression#create"
  post "/track-nudge-click", to: "in_product_messaging_click#create"
  post "/track-nudge-dismissal", to: "in_product_messaging_dismissal#create"
  get "/in-product-messaging/dismiss-and-redirect", to: "in_product_messaging_dismiss_and_redirect#show", as: :dismiss_and_redirect
  get "/in-product-messaging/click-and-redirect", to: "in_product_messaging_click#show", as: :click_and_redirect
  get "/in-product-messaging/dfd-new-tasks-indicator", to: "in_product_messaging_digital_front_door_new_tasks_indicator#show", as: :dfd_new_tasks_indicator
  post "/in-product-messaging/enterprise-dismiss-notice/:notice", to: "in_product_messaging_enterprise_dismiss_notice#create", as: :enterprise_dismiss_notice

  ##
  # App associations
  # Maps paths to configs that would associate dotcom with certain external apps
  unless GitHub.enterprise?
    scope module: :app_associations do
      get "/.well-known/assetlinks.json",                     to: "android_identities#index"
      get "/.well-known/microsoft-identity-association.json", to: "microsoft_identities#index"
    end
  end

  ##
  # "Contact us" page, mostly redirects to support.github.com
  scope module: :site do
    get "/contact",         to: "contact#index",      as: "contact"
    get "/CONTACT",         to: "contact#index",      as: nil
    get "/contact/:flavor", to: "contact#index",      flavor: Regexp.union(GitHub.contact_form_flavors.keys), as: "flavored_contact"
    get "/contact/default", to: redirect("/contact"), format: false
    get "/support",         to: "contact#index"
  end

  ##
  # Legacy Site stuff mostly owned by app_core
  get "/410", to: "feature_gone#index"
  get "/site/assets/:name.:format", to: "asset_redirect#index"
  get "/site/boomtown", to: "boomtown#index"
  get "/site/componenttown", to: "componenttown#index"
  get "/site/force502", to: "force502#index"
  get "/site/keyboard_shortcuts", to: "keyboard_shortcuts#index"
  get "/site/metadata", to: "site_metadata#index"
  get "/site/roletown", to: "roletown#index"
  get "/site/sha", to: "site_sha#index"

  unless GitHub.enterprise?
    get "/site/contexttown", to: "contexttown#index"
    get "/site/sciencetown", to: "sciencetown#index"

    get "/site/sleeptown", to: "sleeptown#index"
    post "/site/custom_sleeptown", to: "sleeptown#create"
  end

  ##

  get  "/_render_node/:id/*path", to: "team_discussion_nodes#show", as: :show_team_discussion_node_partial, constraints: { path: /orgs\/team_discussion.+/ }, legacy: true

  get  "/_graphql/:operation_name", to: "queries#query", as: :graphql
  post "/_graphql/:operation_name", to: "queries#query"

  # A place to send people who we need a verified email from.
  get "/account/unverified-email", to: "unverified_email#index", as: :unverified_email

  # For more information on this, see:
  #   https://github.com/github/customer-feedback/issues/1224
  #
  # We need to route GitHub apps differently on Enterprise
  # so setup the prefix ahead of time.
  app_prefix = GitHub.enterprise? ? "github-apps" : "apps"

  get "/#{app_prefix}/github-actions",        to: redirect("/features/actions") # The GitHub Actions app page will never be revealed to the end-user.
  get "/#{app_prefix}/github/github-actions", to: redirect("/features/actions") # The GitHub Actions app page will never be revealed to the end-user.

  if GitHub.dependabot_enabled?
    get "/#{app_prefix}/dependabot",        to: redirect(GitHub.dependabot_security_updates_help_url)
    get "/#{app_prefix}/github/dependabot", to: redirect(GitHub.dependabot_security_updates_help_url)
  end

  if GitHub.pages_github_app_available?
    get "/#{app_prefix}/github-pages",         to: redirect(GitHub.pages_help_url)
    get "/#{app_prefix}/github/github-pages",  to: redirect(GitHub.pages_help_url)
  end

  get "/#{app_prefix}/github-advanced-security",         to: redirect("https://docs.github.com/get-started/learning-about-github/about-github-advanced-security")
  get "/#{app_prefix}/github/github-advanced-security",  to: redirect("https://docs.github.com/get-started/learning-about-github/about-github-advanced-security")

  # When adding new redirects, be aware that not having access to the App's page might interfere with installations.
  # Usually, a redirect should only be added for Global Apps.
  unless GitHub.enterprise?
    get "/#{app_prefix}/github/git-src-migrator",  to: redirect("https://docs.github.com/en/migrations/using-github-enterprise-importer")
    get "/#{app_prefix}/git-src-migrator",  to: redirect("https://docs.github.com/en/migrations/using-github-enterprise-importer")
    get "/#{app_prefix}/github-merge-queue",  to: redirect("https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue")
    get "/#{app_prefix}/github/github-merge-queue",  to: redirect("/features/code-review")
    get "/#{app_prefix}/github-project-automation",   to: redirect("https://docs.github.com/issues/planning-and-tracking-with-projects/automating-your-project")
    get "/#{app_prefix}/github/github-project-automation",   to: redirect("https://docs.github.com/issues/planning-and-tracking-with-projects/automating-your-project")
    get "/#{app_prefix}/github/merge-commit-update-refs", to: redirect("docs-link")
    get "/#{app_prefix}/merge-commit-update-refs", to: redirect("docs-link")
    get "/#{app_prefix}/github/copilot-pull-request-reviewer", to: redirect("https://gh.io/copilot-code-reviews-docs")
    get "/#{app_prefix}/copilot-pull-request-reviewer", to: redirect("https://gh.io/copilot-code-reviews-docs")
    get "/#{app_prefix}/github/copilot-swe-agent", to: redirect("https://gh.io/copilot-coding-agent-docs")
    get "/#{app_prefix}/copilot-swe-agent", to: redirect("https://gh.io/copilot-coding-agent-docs")

    get "/#{app_prefix}/github/github-campaigns", to: redirect(DocsUrlConfig.url_for("code-security/fixing-security-alerts-at-scale"))
    get "/#{app_prefix}/github-campaigns", to: redirect(DocsUrlConfig.url_for("code-security/fixing-security-alerts-at-scale"))
  end

  if GitHub.enterprise?
    get "/#{app_prefix}/github-project-automation",   to: redirect("https://docs.github.com/en/enterprise-server@latest/issues/planning-and-tracking-with-projects/automating-your-project")
    get "/#{app_prefix}/github/github-project-automation",   to: redirect("https://docs.github.com/en/enterprise-server@latest/issues/planning-and-tracking-with-projects/automating-your-project")
    get "/#{app_prefix}/github-merge-queue",  to: redirect("https://docs.github.com/en/enterprise-server@latest/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue")
    get "/#{app_prefix}/github/merge-commit-update-refs", to: redirect("docs-link")
    get "/#{app_prefix}/merge-commit-update-refs", to: redirect("docs-link")
    get "/#{app_prefix}/github/copilot-reviewer", to: redirect("docs-link")
    get "/#{app_prefix}/copilot-pull-request-reviewer", to: redirect("docs-link")
    get "/#{app_prefix}/github/copilot-swe-agent", to: redirect("docs-link")
    get "/#{app_prefix}/copilot-swe-agent", to: redirect("docs-link")
  end

  if GitHub.codespaces_enabled?
    get "/#{app_prefix}/github-codespaces",        to: redirect("/codespaces")
    get "/#{app_prefix}/github/github-codespaces", to: redirect("/codespaces")
  end

  # IntegrationsListingsController
  scope "/#{app_prefix}" do
    get "/feature/:feature", to: "integration_listings#feature",    as: :"apps_feature"
    get "/:name/install",    to: "integration_listings#install",    as: :"app_install"
    get "/:name/learn_more", to: "integration_listings#learn_more", as: :"app_learn_more"
  end

  get "/#{app_prefix}/#{GitHub.proxima_external_apps_owner_slug}/:id",                      to: "external_integrations#show",             as: :external_app
  get "/#{app_prefix}/#{GitHub.proxima_external_apps_owner_slug}/:id/installation_action",  to: "integrations/installation_actions#show", as: :external_app_installation_action

  get "/#{GitHub.proxima_third_party_apps_path_prefix}/:id",                      to: redirect("/#{app_prefix}/#{GitHub.proxima_external_apps_owner_slug}/%{id}"),          as: :third_party_app
  get "/#{GitHub.proxima_third_party_apps_path_prefix}/:id/installation_action",  to: redirect("/#{app_prefix}/#{GitHub.proxima_external_apps_owner_slug}/%{id}/installation_action"), as: :third_party_app_installation_action

  get "/#{app_prefix}/:id",                     to: "integrations#show",                      as: :alias_app
  get "/#{app_prefix}/:id/installation_action", to: "integrations/installation_actions#show", as: :alias_app_installation_action

  get "/#{app_prefix}/:owner/:id",                     to: "integrations#show",                      as: :user_app
  get "/#{app_prefix}/:owner/:id/installation_action", to: "integrations/installation_actions#show", as: :user_app_installation_action

  get "/#{app_prefix}/businesses/:slug/:id",                     to: "integrations#show",                      as: :business_app
  get "/#{app_prefix}/businesses/:slug/:id/installation_action", to: "integrations/installation_actions#show", as: :business_app_installation_action

  unless GitHub.enterprise?
    get "/#{app_prefix}", to: "integration_listings#index", as: :apps
  end

  app_route_prefixes = {
    "/#{app_prefix}"                                            => "alias_app",
    "/#{app_prefix}/:owner"                                     => "user_app",
    "/#{app_prefix}/businesses/:slug"                           => "business_app",
    "/#{app_prefix}/#{GitHub.proxima_external_apps_owner_slug}" => "external_app",
  }

  # IntegrationInstallationsController
  app_route_prefixes.each do |prefix, helper|
    scope "/#{prefix}" do
      get   "/:integration_id/installations/new",             to: "integration_installations#new",                as: :"new_#{helper}_installation"
      get   "/:integration_id/installations/select_target",   to: "integration_installations#select_target",      as: :"#{helper}_select_target"
      match "/:integration_id/installations/new/permissions", to: "integration_installations#permissions",        as: :"#{helper}_installation_permissions", via: [:get, :post]
      post  "/:integration_id/installations",                 to: "integration_installations#create",             as: :"#{helper}_installations"
      get   "/:integration_id/installations/suggestions",     to: "integration_installations#suggestions",        as: :"#{helper}_installations_suggestions"
      get   "/:integration_id/installations/:id",             to: "integration_installations#edit",               as: :"edit_#{helper}_installation"
      put   "/:integration_id/installations/:id",             to: "integration_installations#update",             as: :"update_#{helper}_installation"
      get   "/:integration_id/installations/:id/permissions", to: "integration_installations#edit_permissions",   as: :"edit_#{helper}_installation_permissions"
      put   "/:integration_id/installations/:id/permissions", to: "integration_installations#update_permissions", as: :"update_#{helper}_installation_permissions"

      delete "/:integration_id/requests/:request_id",         to: "integration_installation_requests#destroy",    as: :"cancel_#{helper}_integration_installation_request"
    end
  end

  # MarketplaceListingsAdminController
  resources :marketplace_listing_admins, only: [:update], as: :marketplace_listing_admins

  # MarketplaceListingsController
  unless GitHub.enterprise?
    marketplace_search_constraint = -> (request) do
      request.query_parameters["query"].present? ||
        request.query_parameters["type"].present? ||
        request.query_parameters["category"].present? ||
        request.query_parameters["verification"].present?
    end

    constraints marketplace_search_constraint do
      get "/marketplace", to: "marketplace/searches#show", as: :marketplace_search
    end

    get    "/marketplace",                                      to: "marketplaces#show",                          as: :marketplace
    get    "/marketplace/search-results/:type",                 to: "marketplaces#show_results",                  as: :marketplace_search_results
    get    "/marketplace/publishers",                           to: "marketplace/searches#suggested_publishers",  as: :marketplace_suggested_publishers
    post   "/marketplace",                                      to: "marketplace_listings#create"
    post   "/marketplace/preview",                              to: "marketplace_listings#preview",               as: :marketplace_preview
    get    "/marketplace/free-trials",                          to: "marketplace_listings#free_trials",           as: :marketplace_free_trials
    get    "/marketplace/orders/pending",                       to: "marketplace/pending_orders#index",           as: :marketplace_pending_orders
    get    "/marketplace/installations/pending",                to: "marketplace/pending_installations#index",    as: :marketplace_pending_installations
    get    "/marketplace/autocomplete/:user_id/orgs",           to: "marketplace/organizations_autocomplete#index", as: :marketplace_autocomplete_user_orgs
    post   "/marketplace/pending_installations/dismiss",        to: "marketplace/pending_installations/dismissals#create", as: :dismiss_marketplace_pending_installations_notice
    delete "/marketplace/previews/:id",                         to: "marketplace_purchases#delete_pending",       as: :delete_pending_marketplace_order
    get    "/marketplace/category/:slug",                       to: "marketplace/searches#show",                  as: :marketplace_category
    get    "/marketplace/new",                                  to: "marketplace_listings#new",                   as: :new_marketplace_listing
    get    "/marketplace/new/:type/:id",                        to: "marketplace_listings#new_with_integratable", as: :new_marketplace_listing_with_integratable
    get    "/marketplace/manage",                               to: "marketplace_listings#manage",                as: :manage_marketplace_listings
    get    "/marketplace/actions",                              to: redirect("/marketplace?type=actions", status: 302), as: :marketplace_actions
    get    "/marketplace/actions/usable_icons",                 to: "marketplace/actions/usable_icons#index",     as: :marketplace_actions_usable_icons
    post   "/marketplace/actions/agreement_signatures",         to: "marketplace/actions/agreement_signatures#create", as: :marketplace_actions_agreement_signatures
    get    "/marketplace/actions/:slug",                        to: "marketplace/actions#show",                   as: :marketplace_action
    get    "/marketplace/actions/:slug/actions_versions",       to: "marketplace/actions_versions#show",          as: :marketplace_action_versions
    delete "/marketplace/actions/:slug",                        to: "marketplace/actions#destroy",                as: :delete_marketplace_action

    if GitHub.models_enabled?
      draw :github_models
      draw :models_byok
    end

    get    "/marketplace/:listing_slug",                        to: "marketplace_listings#show",                  as: :marketplace_listing
    post   "/marketplace/:listing_slug/agreement_signatures",   to: "marketplace_agreement_signatures#create",    as: :marketplace_agreement_signatures
    get    "/marketplace/:listing_slug/plan/:plan_id",          to: "marketplace_listings#show",                  as: :marketplace_listing_preview_plan
    put    "/marketplace/:listing_slug",                        to: "marketplace_listings#update"
    get    "/marketplace/:listing_slug/edit",                   to: "marketplace_listings#edit",                  as: :edit_marketplace_listing
    get    "/marketplace/:listing_slug/edit/overview",          to: redirect("/marketplace/%{listing_slug}/edit") # /overview was moved to /edit
    get    "/marketplace/:listing_slug/edit/description",       to: "marketplace_listings#edit_description",      as: :edit_description_marketplace_listing
    get    "/marketplace/:listing_slug/edit/contact",           to: "marketplace_listings#edit_contact_info",     as: :edit_contact_info_marketplace_listing
    get    "/marketplace/:listing_slug/edit/featured_customers", to: "marketplace/listings/featured_customers#index", as: :edit_featured_customers_marketplace_listing
    put    "/marketplace/:listing_slug/edit/featured_customers", to: "marketplace/listings/featured_customers#update", as: :update_featured_customers_marketplace_listing
    delete "/marketplace/:listing_slug/edit/featured_customers/:id", to: "marketplace/listings/featured_customers#destroy", as: :destroy_featured_customers_marketplace_listing
    post   "/marketplace/:listing_slug/transparency_report_exports", to: "marketplace/listings/transparency_report_exports#create", as: :marketplace_transparency_report_exports

    get    "/marketplace/:listing_slug/install/:subscription_item_id", to: "marketplace_listing_installations#new",      as: :install_marketplace_listing
    get    "/marketplace/:listing_slug/upgrade/:plan_number/:account_id", to: "marketplace_purchases#integrator_upgrade", as: :marketplace_plan_upgrade
    get    "/marketplace/:listing_slug/order/:plan_id",          to: "marketplace_purchases#new",                  as: :marketplace_order
    get    "/marketplace/:listing_slug/order_preview/:plan_id",  to: "marketplace_purchases#preview",              as: :marketplace_order_preview
    post   "/marketplace/:listing_slug/order/:plan_id",          to: "marketplace_purchases#create",               as: :marketplace_order_purchase
    post   "/marketplace/:listing_slug/order/:plan_id/upgrade",  to: "marketplace_purchases#update",               as: :marketplace_order_upgrade
    get    "/marketplace/:listing_slug/screenshots",             to: "marketplace_listings#screenshots",           as: :marketplace_listing_screenshots
    post   "/marketplace/:listing_slug/redraft",                 to: "marketplace_listings#redraft",               as: :redraft_marketplace_listing
    put    "/marketplace/:listing_slug/screenshot/:id",          to: "marketplace_listing_screenshots#update"
    delete "/marketplace/:listing_slug/screenshot/:id",          to: "marketplace_listing_screenshots#destroy",    as: :marketplace_listing_screenshot
    post   "/marketplace/:listing_slug/request_unverified_approval", to: "marketplace/listings/unverified_approval_requests#create", as: :unverified_listing_approval_request
    post   "/marketplace/:listing_slug/request_verified_financial_approval/:id", to: "marketplace/listings/verified_approval_requests#initiate_financial_approval", as: :verified_financial_listing_approval_request
    post   "/marketplace/:listing_slug/request_verified_approval", to: "marketplace/listings/verified_approval_requests#create", as: :verified_listing_approval_request
    get    "/marketplace/:listing_slug/edit/plans",              to: "marketplace_listing_plans#index",            as: :marketplace_listing_plans
    get    "/marketplace/:listing_slug/edit/plans/new",          to: "marketplace_listing_plans#new",              as: :new_marketplace_listing_plan
    get    "/marketplace/:listing_slug/edit/plans/:id",          to: "marketplace_listing_plans#show",             as: :marketplace_listing_plan
    post   "/marketplace/:listing_slug/edit/plans",              to: "marketplace_listing_plans#create"
    put    "/marketplace/:listing_slug/edit/plans/:id",          to: "marketplace_listing_plans#update"
    delete "/marketplace/:listing_slug/edit/plans/:id",          to: "marketplace_listing_plans#destroy"
    put "/marketplace/:listing_slug/edit/plans/:id/retire",            to: "marketplace_listing_plans#retire",            as: :retire_marketplace_listing_plan
    put "/marketplace/:listing_slug/edit/plans/:id/publish",           to: "marketplace_listing_plans#publish",           as: :publish_marketplace_listing_plan
    get    "/marketplace/:listing_slug/hook",                    to: "marketplace_listing_hooks#show",              as: :marketplace_listing_hook
    post   "/marketplace/:listing_slug/hook",                    to: "marketplace_listing_hooks#create"
    put    "/marketplace/:listing_slug/hook",                    to: "marketplace_listing_hooks#update"
    patch  "/marketplace/:listing_slug/hook",                    to: "marketplace_listing_hooks#update"
    get    "/marketplace/:listing_slug/sync",                    to: "marketplace_listing_sync#show",                     as: :marketplace_listing_sync
    put    "/marketplace/:listing_slug/sync",                    to: "marketplace_listing_sync#update"
    get    "/marketplace/:listing_slug/security_compliance",     to: "marketplace_listing_security_and_compliance#show",   as: :marketplace_listing_security_compliance
    put    "/marketplace/:listing_slug/security_compliance",     to: "marketplace_listing_security_and_compliance#update", as: :marketplace_listing_security_compliance_update

    constraints(guid: WEBHOOK_GUID_REGEX, id: WEBHOOK_REGEX, hook_id: /\d+/) do
      get  "/marketplace/:listing_slug/hook/:hook_id/deliveries",                     to: "hook_deliveries#index",     as: :marketplace_listing_hook_deliveries, context: "marketplace_listing"
      get  "/marketplace/:listing_slug/hook/:hook_id/deliveries/:id",                 to: "hook_deliveries#show",      as: :marketplace_listing_hook_delivery, context: "marketplace_listing"
      get  "/marketplace/:listing_slug/hook/:hook_id/deliveries/:id/payload.:format", to: "hook_deliveries#payload",   as: :marketplace_listing_delivery_payload, format: "json", context: "marketplace_listing"
      get  "/marketplace/:listing_slug/hook/:hook_id/redeliveries",                     to: "hook_deliveries#redeliveries",     as: :marketplace_listing_hook_redeliveries, context: "marketplace_listing"
      post "/marketplace/:listing_slug/hook/:hook_id/deliveries/:guid/redeliver",       to: "hook_deliveries#redeliver", as: :marketplace_listing_redeliver_hook_delivery, context: "marketplace_listing"
    end

    get    "/marketplace/:listing_slug/insights",                to: "marketplace_listing_insights#index",
      as: :marketplace_listing_insights
    get    "/marketplace/:listing_slug/insights/visitor_graph_data",    to: "marketplace_listing_insights#visitor_graph_data",
      as: :marketplace_listing_insights_visitor_graph_data
    get    "/marketplace/:listing_slug/insights/transactions",          to: "marketplace_listing_transactions#index",
      as: :marketplace_listing_insights_transactions
    get    "/marketplace/:listing_slug/insights/inactive_customers",    to: "marketplace/listings/insights/inactive_customers#index",
      as: :marketplace_listing_insights_inactive_customers

    get "/works-with", to: redirect("/marketplace")
    get "/works-with/new", to: redirect("/marketplace")
    get "/works-with/category/:slug", to: redirect("/marketplace")
    get "/works-with/:listing_id/edit", to: redirect("/marketplace")
  end

  get "/feed_posts/embeds", to: "feed_posts/embeds#show", as: :feed_post_embed
  resources :feed_posts, only: [:create, :destroy] do
    put "/reactions", to: "reactions#update", as: :update_reaction
    resources :comments, only: [:create, :destroy, :index], controller: "feed_posts/comments" do
      put "/reactions", to: "reactions#update", as: :update_reaction
    end
  end
  get "/feed_posts/tags_menu", to: "feed_posts/tags_menu#index", as: :feed_post_tags_menu

  resources :discover_people, only: [:index]

  ##
  # GitHub Sponsors
  draw :sponsors

  ##
  # GitHub Spark Waitlist
  get   "/github_spark_waitlist_signup",           to: "github_spark_waitlist_signup#new",    as: :github_spark_waitlist_signup
  get   "/github_spark_waitlist_signup/join",      to: "github_spark_waitlist_signup#join",   as: :github_spark_waitlist_signup_join
  post  "/github_spark_waitlist_signup",           to: "github_spark_waitlist_signup#create", as: :github_spark_waitlist_signup_create
  get   "/github_spark_waitlist",                  to: redirect("/github_spark_waitlist_signup")
  get   "/github_spark_waitlist/join",             to: redirect("/github_spark_waitlist_signup/join")


  # RepositoryInvitationsController
  get "/:user_id/:repository/invitations", to: "repository_invitations#show", as: :repository_invitation, repository: REPO_REGEX
  post "repository_invitations/:invitation_id/accept", to: "repository_invitations#accept", as: :repository_invitation_accept
  post "repository_invitations/:invitation_id/reject", to: "repository_invitations#reject", as: :repository_invitation_reject
  post "repository_invitations/:invitation_id/block_inviter", to: "repository_invitations#block_inviter", as: :block_repository_inviter
  put "repository_invitations/:invitation_id/set_permissions", to: "repository_invitations#set_permissions", as: :repository_invitation_permissions

  # RepositoryAccessRequestControler - Used for staff access requests when temporarily unlocking private repos
  get "/:user_id/:repository/access_request/:id", to: "repos/access_request#show", as: :repository_access_request, repository: REPO_REGEX
  post "/:user_id/:repository/access_request/:id/consent", to: "repos/access_request#consent", as: :repository_access_request_consent, repository: REPO_REGEX

  # SubscriptionItemsController
  delete "/subscription_items/:id", to: "subscription_items#destroy", as: :subscription_item

  # Gitignore templates
  get "/site/gitignore/templates", to: "gitignore#index", as: :gitignore_templates, format: :json
  get "/site/gitignore/:template", to: "gitignore#show",  as: :gitignore_template, template: /[\w\.\+-]+/

  get "_jobs/:id", to: "copilot_jobs#show", as: :copilot_job_status, constraints: { id: /copilot-completion.+/ }
  get "/_jobs/:id", to: "jobs#show", as: :job_status

  ##
  # Styleguide
  unless GitHub.enterprise?
    get "/styleguide/*path", to: "styleguide#index"
    get "/styleguide",       to: "styleguide#index"
  end

  ##
  # Developer program
  unless GitHub.enterprise?
    get "/developer", to: redirect(GitHub.developer_help_url)

    get    "/developer/register", to: "developer_program_membership#new", as: "register_developer_program"
    post   "/developer/register", to: "developer_program_membership#create"
    get    "/developer/thanks",   to: "developer_program_membership#show", as: "thanks_developer_program"

    put    "/developer/membership", to: "developer_program_membership#update", as: "developer_program_membership"
    delete "/developer/membership", to: "developer_program_membership#destroy"
  end

  ##
  # Identicons for GitHub and OAuth apps
  get "/identicons/app/:type/:id", to: "app_identicons#show", as: :app_identicon, defaults: { format: :svg }

  ##
  # Identicons for users
  get "/identicons/:id.png",          to: "identicons#show", as: :identicon,       constraints: { id: /[a-z0-9]{32}/ }
  get "/identicons/via_email",        to: "identicons#show", as: :email_identicon
  get "/identicons/:user_login.png",  to: "identicons#show", as: :user_identicon

  get "/orgs/improved-permissions", to: "orgs/marketing#index", as: :orgs_marketing

  # team sync url for Orgs
  get "orgs/team-sync/azure-callback", to: "orgs/team_sync#azure_callback",             as: :team_sync_azure_callback

  scope "/memexes/:memex_id" do
    post   "/views", to: "memexes/views#create", as: :create_memex_view
    delete "/views", to: "memexes/views#destroy", as: :destroy_memex_view
    put    "/views", to: "memexes/views#update", as: :update_memex_view

    get   "/copy_project_partial", to: "memexes/partials#new", as: :copy_memex_project_partial

    post "/templates", to: "memexes/templates#create", as: :create_memex_template

    get    "/charts/query",         to: "memexes/charts#show",    as: :memex_chart
    get    "/charts",               to: "memexes/charts#index",   as: :memex_charts
    post   "/charts",               to: "memexes/charts#create",  as: :create_memex_chart
    put    "/charts",               to: "memexes/charts#update",  as: :update_memex_chart
    delete "/charts",               to: "memexes/charts#destroy", as: :destroy_memex_chart

    get     "/columns",                          to: "memexes/columns#index",    as: :memex_columns
    get     "/columns/:memex_project_column_id", to: "memexes/columns#show",     as: :memex_column
    post    "/columns",                          to: "memexes/columns#create",   as: :create_memex_column
    put     "/columns",                          to: "memexes/columns#update",   as: :update_memex_column
    delete  "/columns",                          to: "memexes/columns#destroy",  as: :destroy_memex_column

    get    "/paginated_items", to: "memexes/items#index",           as: :memex_items
    get    "/items",           to: "memexes/items#get",             as: :get_memex_item
    post   "/items",           to: "memexes/items#create",          as: :create_memex_item
    put    "/items",           to: "memexes/items#update",          as: :update_memex_item
    delete "/items",           to: "memexes/items#destroy",         as: :destroy_memex_items

    post   "/items/convert",   to: "memexes/items#convert_to_issue", as: :convert_to_issue_memex_items
    post   "/items/archive",   to: "memexes/items/archive#create", as: :archive_memex_items
    put    "/items/unarchive", to: "memexes/items/archive#update", as: :unarchive_memex_items
    get    "/items/archived",  to: "memexes/items#legacy_archived_items", as: :memex_legacy_archived_items
    get    "/items/archive/status",  to: "memexes/items#legacy_archive_status", as: :memex_legacy_archive_status

    post   "/items/reindex",   to: "memexes/items#reindex", as: :reindex_memex_items

    post   "/items/bulk", to: "memexes/items/bulk_actions#create",  as: :create_memex_items_bulk
    put    "/items/bulk", to: "memexes/items/bulk_actions#update", as: :update_memex_items_bulk
    get    "/items/:memex_project_item_id/edit_form", to: "memexes/items#edit_form", as: :edit_form_memex_item
    get    "/items/parent", to: "memexes/items#tracked_by_parent", as: :memex_items_tracked_by_parent

    get "/migrate", to: "memexes/migration#show", as: :memex_project_migration
    post "/migrate", to: "memexes/migration_retries#create", as: :memex_retry_migration
    delete "/migrate", to: "memexes/migration_retries#destroy", as: :memex_cancel_migration
    post "/migrate/acknowledge_completion", to: "memexes/migration#create", as: :memex_acknowledge_completion_migration

    get  "/side_panel_item", to: "memexes/side_panel_item#show", as: :memex_get_sidepanel_item
    post "/side_panel_item/comment", to: "memexes/side_panel_item/comments#create", as: :memex_comment_on_sidepanel_item
    put  "/side_panel_item/comment", to: "memexes/side_panel_item#edit_comment", as: :memex_edit_sidepanel_comment
    post "/side_panel_item/update_state", to: "memexes/side_panel_item#update_state", as: :memex_update_sidepanel_item_state
    post "/side_panel_item/update_reaction", to: "memexes/side_panel_item#update_reaction", as: :memex_update_sidepanel_item_reaction
    post "/side_panel_item/update", to: "memexes/side_panel_item#update", as: :memex_update_sidepanel_item
    get  "/side_panel_item/suggestions",  to: "memexes/side_panel_item#suggestions", as: :memex_sidepanel_item_suggestions

    get  "/suggested_organizations", to: "memexes/suggested_organizations#index", as: :memex_suggested_copy_organizations

    get    "/items/suggestions/assignees",  to: "memexes/items/suggested_assignees#index", as: :memex_item_suggested_assignees
    get    "/items/suggestions/labels",     to: "memexes/items/suggested_labels#index", as: :memex_item_suggested_labels
    get    "/items/suggestions/milestones", to: "memexes/items#suggested_milestones", as: :memex_item_suggested_milestones
    get    "/items/suggestions/issue_types", to: "memexes/items/suggested_issue_types#index", as: :memex_item_suggested_issue_types

    post   "/column_options", to: "memexes/column_options#create", as: :create_memex_project_column_option
    put    "/column_options", to: "memexes/column_options#update", as: :update_memex_project_column_option
    delete "/column_options", to: "memexes/column_options#destroy", as: :destroy_memex_project_column_option

    get    "/default_workflows",       to: "memexes/workflows#defaults", as: :memex_project_default_workflows
    get    "/workflow_configurations", to: "memexes/workflows_configuration#index", as: :memex_project_workflow_configurations
    get    "/workflows",               to: "memexes/workflows#index", as: :memex_project_workflows
    post   "/workflows",               to: "memexes/workflows#create", as: :create_memex_project_workflow
    put    "/workflows",               to: "memexes/workflows#update", as: :update_memex_project_workflow

    get    "/settings/collaborators",                to: "memexes/settings/collaborators#index", as: :memex_collaborators
    post   "/settings/collaborators",                to: "memexes/settings/collaborators#update", as: :memex_update_collaborators
    delete "/settings/collaborators",                to: "memexes/settings/collaborators#destroy", as: :memex_remove_collaborators
    get    "/settings/collaborators/suggestions",    to: "memexes/settings/suggested_collaborators#index", as: :memex_suggested_collaborators
    put    "/settings/organization_access",          to: "memexes/settings#update_organization_access", as: :memex_update_organization_access
    get    "/settings/organization_access",          to: "memexes/settings#get_organization_access", as: :memex_get_organization_access

    get    "/statuses",     to: "memexes/statuses#index",   as: :memex_statuses
    post   "/statuses",     to: "memexes/statuses#create",  as: :create_memex_status
    put    "/statuses",     to: "memexes/statuses#update",  as: :update_memex_status
    delete "/statuses/:id", to: "memexes/statuses#destroy",  as: :destroy_memex_status

    post "/notifications/subscribe", to: "memexes/notification_subscriptions#create", as: :subscribe_memex_notification_subscription
    delete "/notifications/unsubscribe", to: "memexes/notification_subscriptions#destroy", as: :unsubscribe_memex_notification_subscription
    get "/hovercard", to: "hovercards/memexes#show", as: :memex_hovercard
  end

  # Organization settings routes
  scope "/organizations/:organization_id",
    constraints: { organization_id: USERID_REGEX },
    module: :orgs,
    as: :organization do

    scope module: :settings do
      resource :settings, only: [] do
        resources :blocked_users, only: [:index, :create, :destroy, :update], param: :login do
          collection do
            resources :suggestions,
              module: :blocked_users,
              only: :index,
              as: :blocked_users_suggestions
          end
        end

        resources :moderators, only: [:index, :create, :destroy] do
          collection do
            resources :suggestions,
              module: :moderators,
              only: :index,
              as: :moderators_suggestions
          end
        end

        resource :discussions, only: [:show, :update] do
          resources :selected_repositories,
            module: :discussions,
            only: :index
        end

        resource :member_feature_requests, only: [:show] do
          resource :subscription, only: [:create, :destroy, :update], controller: "member_feature_requests/subscriptions"
        end
        post "/member_feature_requests/subscribe",                 to: "member_feature_requests_#subscribe",       as: :member_feature_requests_subscribe

        resource :soft_deletion, only: :create, controller: "soft_deletion"

        resources :compliance, only: :index

        resources :licensing, only: [:index]
        resources :payment_history, only: [:index]
      end
    end
  end

  scope "/orgs/:org", constraints: { org: USERID_REGEX } do
    org = self

    org.get   "/",                      to: "orgs/repositories#index",      as: :org_root
    org.get   "/repositories",          to: "orgs/repositories#show",       as: :org_repositories
    org.get   "/repos_list",            to: "orgs/repositories#repos_list", as: :org_repos_list, format: :json
    org.get   "/hovercard",             to: "hovercards/organizations#show"

    resource :search, only: [:show], module: :orgs, as: :org_search

    org.get   "/top_languages", to: "orgs/top_languages#index", as: :org_top_languages

    org.get   "/dashboard/pulls",       to: "issues#redirect_to_scoped_org_dashboard", as: :org_pulls_dashboard, pulls_only: true
    org.get   "/dashboard/issues",      to: "issues#redirect_to_scoped_org_dashboard", as: :org_issues_dashboard

    org.put   "/application_access",                              to: "orgs/oauth_application_policy#update",  as: :org_application_access
    org.post  "/policies/applications/:application_id/request",   to: "orgs/oauth_application_approvals#request_approval", as: :org_request_oauth_app_approval
    org.get   "/policies/applications/:application_id",           to: "orgs/oauth_application_approvals#show", as: :org_application_approval
    org.put   "/policies/applications/:application_id/set_state", to: "orgs/oauth_application_approvals#set_state", as: :org_set_application_approval_state

    org.delete  "/removed_member_notifications",                           to: "orgs/removed_member_notifications#destroy", as: :org_destroy_removed_member_notifications

    org.get     "/followers",                                               to: "orgs/followers#index", as: :org_followers

    org.get     "/people",                                                 to: "orgs/people#index", as: :org_people
    org.get "/member_details",
      to: "orgs/member_details#index",
      as: :org_member_details
    org.get "/outside_collaborator_details",
      to: "orgs/outside_collaborator_details#index",
      as: :org_outside_collaborator_details
    org.get "/people/enterprise_owners",
      to: "orgs/people/enterprise_owners#index",
      as: :org_enterprise_owners
    org.get "/people/security_managers",
      to: "orgs/people/security_managers#index",
      as: :org_security_managers
    org.put     "/people/set_role",                                        to: "orgs/people/role#update", as: :org_set_role
    org.delete  "/people/destroy_members",                                 to: "orgs/people/members#destroy", as: :org_destroy_people
    org.delete  "/people/destroy_invitations",                             to: "orgs/people/pending_invitations#destroy", as: :org_destroy_invitations
    org.delete  "/people/destroy_failed_invitations",                      to: "orgs/people/failed_invitations#destroy", as: :org_destroy_failed_invitations
    org.post    "/people/retry_failed_invitations",                        to: "orgs/people/failed_invitations#update", as: :org_retry_failed_invitations
    org.post    "/people/retry_invitations",                               to: "orgs/people/pending_invitations#update", as: :org_retry_invitations
    org.post    "/people/add_member_for_new_org",                          to: "orgs/initial_members#create", as: :add_member_for_new_org
    org.post    "/people/add_member_to_org",                               to: "orgs/people/members#create", as: :add_member_to_org
    org.patch   "/people/business_owner_change_role",                      to: "orgs/people/business_owner_role#update", as: :business_owner_change_role
    org.delete  "/people/destroy_member_for_new_org",                      to: "orgs/initial_members#destroy", as: :destroy_member_for_new_org
    org.get     "/people/destroy_members_dialog",                          to: "orgs/people/destroy_members_dialog#show", as: :org_destroy_people_dialog
    org.put     "/people/set_visibility",                                  to: "orgs/people/visibility#update", as: :org_set_people_visibility
    org.get     "/people/failed_invitations",                              to: "orgs/people/failed_invitations#index", as: :org_failed_invitations
    org.get     "/people/failed_invitation_toolbar_actions",               to: "orgs/people/failed_invitation_toolbar_actions#show", as: :org_failed_invitation_toolbar_actions
    org.get     "/people/pending_invitations",                             to: "orgs/people/pending_invitations#index", as: :org_pending_invitations
    org.get     "/people/pending_invitation_toolbar_actions",              to: "orgs/people/pending_invitation_toolbar_actions#show", as: :org_pending_invitation_toolbar_actions
    org.get     "/people/toolbar_actions",                                 to: "orgs/people/members_toolbar_actions#show", as: :org_members_toolbar_actions
    org.get     "/people/invitations_action_dialog",                       to: "orgs/people/invitations_action_dialog#show", as: :org_invitations_action_dialog
    org.post    "/people/dismiss_membership_banner",                       to: "orgs/people/membership_banner_dismissals#create", as: :org_people_dismiss_membership_banner
    org.post    "/people/convert_to_outside_collaborators",                to: "orgs/people/outside_collaborators#create", as: :org_people_convert_to_outside_collaborators
    org.get     "/people/guest_collaborators",                             to: "orgs/people/guest_collaborators#index", as: :org_guest_collaborators
    org.delete  "/people/remove-outside-collaborators", to: "orgs/people/outside_collaborators#destroy", as: :org_people_remove_outside_collaborators

    org.get     "/people/:person_login",                                   to: "orgs/people#show", as: :org_person
    org.get     "/people/:person_login/repositories/:user_id/:repository", to: "orgs/people/repository_permissions#show", as: :repository_permissions, repository: REPO_REGEX
    org.delete  "/people/:person_login/repositories/:user_id/:repository", to: "orgs/people/repository_permissions#destroy", repository: REPO_REGEX
    org.get     "/people/:person_login/sso",                               to: "orgs/people/sso#index", as: :org_person_sso
    org.delete  "/people/:person_login/sso_session/:session_id",           to: "orgs/people/sso_sessions#destroy", as: :org_person_revoke_sso_session
    org.delete  "/people/:person_login/sso_token/:token_id",               to: "orgs/people/credential_authorizations#destroy", as: :org_person_revoke_sso_token
    org.delete  "/people/:person_login/external_identity",                 to: "orgs/people/external_identities#destroy", as: :org_person_unlink_identity
    org.get     "/outside-collaborators", to: "orgs/people/outside_collaborators#index", as: :org_outside_collaborators
    org.get     "/outside_collaborators/toolbar_actions",                  to: "orgs/people/outside_collaborators_toolbar_actions#show", as: :org_outside_collaborators_toolbar_actions
    org.get     "/pending_collaborators", to: "orgs/people/pending_collaborators#index", as: :org_pending_collaborators
    org.get     "/pending_collaborator_invitations/toolbar_actions", to: "orgs/people/pending_collaborator_invitation_actions#show", as: :org_pending_collaborator_invitations_toolbar_actions
    org.delete  "/people/cancel_pending_collaborator_invitations", to: "orgs/people/pending_collaborators#destroy", as: :org_people_cancel_pending_collaborator_invitations
    org.get     "/tab_counts", to: "orgs/people/tab_counts#index", as: :orgs_people_tab_counts

    org.get    "packages", to: "orgs/packages#index", as: :org_packages

    ## Memexes/Projects
    # These specific routes must exist before the /:number routes below
    org.get    "memexes",                                            to: redirect(status: 307, path: "/orgs/%{org}/projects"), as: false
    org.get    "projects/new/linkable_repositories",                 to: "orgs/projects#linkable_repositories", as: :new_org_project_linkable_repositories
    org.get    "projects/:number/edit",                              to: "orgs/projects#edit", as: :edit_org_project
    org.get    "projects/search",                                    to: redirect(status: 307) { |params, request|
      query_params = request.query_parameters
      new_params = query_params.except(:type)
      "/orgs/#{ params[:org] }/projects/search#{ new_params.empty? ? "" : "?#{new_params.to_param}" }"
    }, as: false, constraints: -> (request) { %w[beta new].include?(request.query_parameters[:type]) }
    org.get    "projects/search",                                    to: "orgs/memexes#search", as: :search_org_projects

    org.get    "projects/templates",                                 to: "orgs/memexes#templates", as: :memex_org_templates

    ## Show routes for projects and memexes
    org.get    "memexes/:memex_number",                              to: "orgs/memexes#redirect_to_projects_url", as: false
    # The constraint here will ensure we render the memex with the number if it exists/flags are enabled etc
    # If the constraint fails we will fall through to trying to render the project with the given number
    org.get    "projects/:memex_number(/views/:view_number)",        to: "orgs/memexes#show", constraints: org_memex_exists_constraint, as: :show_org_memex
    org.get    "projects/:memex_number/assets/:user/:guid",          to: "orgs/memexes_assets#show", as: :org_memex_assets, format: false, constraints: org_memex_exists_constraint
    org.get    "projects/:memex_number/insights(/:chart_number)",    to: "orgs/memexes#show", constraints: org_memex_exists_constraint, defaults: { insights: true }
    org.get    "projects/:memex_number/*paths",        to: "orgs/memexes#show", constraints: org_memex_exists_constraint
    org.get    "projects/:number",                                   to: "orgs/projects#show", as: :org_project

    org.post   "memexes",                                            to: "orgs/memexes#create", as: :create_org_memex

    # AJAX requests that may reference an individual memex via params
    org.get    "projects/beta/search/repositories",                        to: "orgs/memexes#search_repositories", as: :org_memex_search_repositories
    org.get    "projects/beta/search/issues_and_pulls",                    to: "orgs/memexes#search_issues_and_pulls", as: :org_memex_search_issues_and_pulls
    org.get    "projects/beta/suggestions/repositories",                   to: "orgs/memexes#suggested_repositories", as: :org_memex_suggested_repositories
    org.get    "projects/beta/count/issues_and_pulls",                     to: "orgs/memexes#count_issues_and_pulls", as: :org_memex_count_issues_and_pulls

    org.put    "projects/beta/dismiss_legacy_org_banner", to: "orgs/memexes#dismiss_legacy_org_banner", as: :org_memex_dismiss_legacy_org_banner

    # Scoped to a single memex
    # New routes for ajax requests for a memex should be added here.
    scope "/projects/beta/:memex_number" do
      org_memex = self

      org_memex.put       "/",                       to: "orgs/memexes#update", as: :update_org_memex
      org_memex.delete    "/",                       to: "orgs/memexes#delete", as: :delete_org_memex
      org_memex.post      "/_stats",                 to: "orgs/memexes#stats", as: :org_memex_stats
      org_memex.post      "/copy",                   to: "orgs/memexes#copy",  as: :copy_org_memex
      org_memex.get       "/refresh",                to: "orgs/memexes#refresh", as: :refresh_org_memex
      org_memex.delete    "/remove_visited",         to: "orgs/memexes#remove_visited", as: :remove_visited_org_memex
      org_memex.post      "/mwl_beta_signup",        to: "orgs/memexes#memex_without_limits_beta_signup", as: :org_memex_without_limits_beta_signup
      org_memex.post      "/dismiss_notice",         to: "orgs/memexes#dismiss_notice", as: :org_memex_dismiss_notice

      org_memex.get       "/filter_suggestions",     to: "orgs/memexes#filter_suggestions", as: :org_memex_filter_suggestions
    end

    org.get "projects", to: redirect(status: 307) { |params, request|
      new_params = request.query_parameters.except(:type)
      "/orgs/#{params[:org]}/projects#{new_params.empty? ? "" : "?#{new_params.to_param}"}"
    }, as: false, constraints: -> (request) { %w[beta new].include?(request.query_parameters[:type]) }
    org.get    "projects",                           to: "orgs/projects#index", as: :org_projects, constraints: lambda { |request| request.query_parameters[:type] == "classic" }
    org.get    "projects",                           to: "orgs/memexes#index", as: :org_projects_beta

    org.delete "projects",                           to: "orgs/projects#destroy"
    org.post   "projects",                           to: "orgs/memexes#create", as: :create_org_project_beta, constraints: lambda { |request| request.query_parameters[:type] == "beta" || request.query_parameters[:type] == "new" }
    org.put    "projects/:number",                   to: "orgs/projects#update"
    org.put    "projects/:number/state",             to: "orgs/projects#update_state", as: :update_org_project_state
    org.post   "projects/:number/clone",             to: "orgs/projects#clone", as: :org_project_clone
    org.post   "projects/:number/migrate",           to: "orgs/projects#migrate", as: :org_project_migrate
    org.delete "projects/:number/dismiss_notice", to: "orgs/projects#dismiss_notice", as: :org_dismiss_project_notice
    org.get    "projects/:number/migration_status",   to: "orgs/projects#migration_status_notice_partial", as: :org_project_migration_status_notice_partial

    org.get    "projects/:number/search_results", to: "orgs/projects#search_results", as: :org_project_search_results
    org.get    "projects/:number/repository_results", to: "orgs/projects#repository_results", as: :org_project_repository_results
    org.get    "projects/:number/target_owner_results", to: "orgs/projects#target_owner_results", as: :org_project_target_owner_results
    org.get    "projects/:number/activity", to: "orgs/projects#activity", as: :org_project_activity
    org.get    "projects/:number/add_cards_link", to: "orgs/projects#add_cards_link", as: :org_project_add_cards_link
    org.get    "projects/:number/linkable_repositories", to: "orgs/projects#linkable_repositories"

    org.get    "topics", to: "orgs/topics#index", as: :org_topics
    org.get    "topics/most_used", to: "orgs/topics#most_used", as: :org_most_used_topics

    scope "/security", module: "orgs/security_center", as: :security_center do
      resources :options, only: [:index]

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
      end

      resources :assessments, only: [:index, :create], controller: :secret_risk_assessments do
        collection do
          get :json
          get :"results-csv"
          get :"has-config-conflict"
          patch :"enable-ghsp"
        end
      end

      namespace :metrics do
        resource :enablement, controller: :enablement_trends, only: [] do
          get :index
          get :"enablement-trends", format: :json
        end

        resource :dependabot, controller: :dependabot, only: [] do
          get :index

          defaults format: :json do
            get :"alerts-fixed"
            get :"alert-trends-by-status"
            get :"alert-trends-by-severity"
            get :repositories
            get :"alerts-funnel"
          end
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
      end

      resources :tab_counts, only: [:index]
    end

    org.get     "/security", to: redirect(path: "/orgs/%{org}/security/overview", status: 302), as: :security_center_navigation_tab
    org.get     "/security/coverage", to: "orgs/security_center/coverage#index", as: :security_center_coverage
    org.get     "/security/coverage/statuses/:feature", to: "orgs/security_center/coverage#feature_status", as: :security_center_coverage_feature_status
    org.get     "/security/coverage/stats", to: "orgs/security_center/coverage#stats", as: :security_center_coverage_stats
    org.get     "/security/coverage/counts", to: "orgs/security_center/coverage#counts", as: :security_center_coverage_counts
    org.get     "/security/coverage/export", to: "orgs/security_center/coverage_export#show", format: :csv, as: :security_center_coverage_get_export
    org.post    "/security/coverage/export", to: "orgs/security_center/coverage_export#create", format: :json, as: :security_center_coverage_create_export
    org.get     "/security/risk", to: "orgs/security_center/risk#index", as: :security_center_risk
    org.get     "/security/risk/stats", to: "orgs/security_center/risk#stats", as: :security_center_risk_stats
    org.get     "/security/risk/counts", to: "orgs/security_center/risk#counts", as: :security_center_risk_counts
    org.get     "/security/risk/export", to: "orgs/security_center/risk_export#show", format: :csv, as: :security_center_risk_get_export
    org.post    "/security/risk/export", to: "orgs/security_center/risk_export#create", format: :json, as: :security_center_risk_create_export
    org.scope   "/security/overview/export" do
      org.get     "/", to: "orgs/security_center/overview_dashboard_export#show", format: :csv, as: :security_center_overview_dashboard_get_export
      org.post    "/", to: "orgs/security_center/overview_dashboard_export#create", as: :security_center_overview_dashboard_create_export
    end
    org.scope   "/security/metrics/secret-scanning" do
      secret_scanning_metrics_controller = "orgs/security_center/metrics/secret_scanning"
      org.get     "/", to: "#{secret_scanning_metrics_controller}#index", as: :security_center_secret_scanning_metrics
      org.scope   "/push-protection-metrics" do
        org.get     "/", to: "#{secret_scanning_metrics_controller}#push_protection_metrics", as: :security_center_secret_scanning_metrics_push_protection_metrics
        org.get     "/block-counts-by-token-type", to: "#{secret_scanning_metrics_controller}#block_counts_by_token_type", as: :security_center_secret_scanning_metrics_push_protection_metrics_block_counts_by_token_type
        org.get     "/block-counts-by-repo", to: "#{secret_scanning_metrics_controller}#block_counts_by_repo", as: :security_center_secret_scanning_metrics_push_protection_metrics_block_counts_by_repo
        org.get     "/bypass-counts-by-token-type", to: "#{secret_scanning_metrics_controller}#bypass_counts_by_token_type", as: :security_center_secret_scanning_metrics_push_protection_metrics_bypass_counts_by_token_type
        org.get     "/bypass-counts-by-repo", to: "#{secret_scanning_metrics_controller}#bypass_counts_by_repo", as: :security_center_secret_scanning_metrics_push_protection_metrics_bypass_counts_by_repo
      end
    end
    # OrganizationSecretScanningBypassRequestsController
    org.get "/security/bypass-requests/secret-scanning", to: "orgs/organization_secret_scanning_bypass_requests#index", as: :organization_secret_scanning_bypass_requests
    org.get "/security/bypass-requests/secret-scanning/requesters", to: "orgs/organization_secret_scanning_bypass_requests#bypass_request_requesters", as: :organization_secret_scanning_bypass_request_requesters
    org.get "/security/bypass-requests/secret-scanning/approvers", to: "orgs/organization_secret_scanning_bypass_requests#bypass_request_approvers", as: :organization_secret_scanning_bypass_request_approvers
    org.get "/security/bypass-requests/secret-scanning/repo_suggestions", to: "orgs/code_rulesets#ruleset_repo_suggestions"
    # OrganizationSecretScanningBypassRequestsCountsController
    org.get "/security/bypass-requests/secret-scanning/count", to: "orgs/organization_secret_scanning_bypass_requests_counts#index", as: :organization_secret_scanning_bypass_requests_counts

    # OrganizationSecretScanningClosureRequestsController
    org.get "/security/closure-requests/secret-scanning", to: "orgs/organization_secret_scanning_closure_requests#index", as: :organization_secret_scanning_closure_requests
    org.get "/security/closure-requests/secret-scanning/requesters", to: "orgs/organization_secret_scanning_closure_requests#closure_request_requesters", as: :organization_secret_scanning_closure_request_requesters
    org.get "/security/closure-requests/secret-scanning/approvers", to: "orgs/organization_secret_scanning_closure_requests#closure_request_approvers", as: :organization_secret_scanning_closure_request_approvers
    org.get "/security/closure-requests/secret-scanning/repo_suggestions", to: "orgs/code_rulesets#ruleset_repo_suggestions"
    org.get "/security/closure-requests/secret-scanning/count", to: "orgs/organization_secret_scanning_closure_requests#counts", as: :organization_secret_scanning_closure_requests_counts

    # OrganizationCodeScanningAlertDismissalRequestsController
    org.get "/security/bypass-requests/code-scanning", to: "orgs/security_center/code_scanning_alert_dismissal_requests#index", as: :organization_code_scanning_alert_dismissal_requests
    org.get "/security/bypass-requests/code-scanning/requesters", to: "orgs/security_center/code_scanning_alert_dismissal_requests#bypass_request_requesters", as: :organization_code_scanning_alert_dismissal_request_requesters
    org.get "/security/bypass-requests/code-scanning/repo_suggestions", to: "orgs/code_rulesets#ruleset_repo_suggestions"
    org.get "/security/bypass-requests/code-scanning/approvers", to: "orgs/security_center/code_scanning_alert_dismissal_requests#bypass_request_approvers", as: :organization_code_scanning_alert_dismissal_request_approvers

    org.get     "/security/alerts/secret-scanning", to: "orgs/security_center/secret_scanning#index", as: :security_center_alerts_secret_scanning
    org.get     "/security/alerts/secret-scanning/menu-content", to: "orgs/security_center/secret_scanning#menu_content", as: :security_center_alerts_secret_scanning_menu_content
    org.get     "/security/alerts/secret-scanning/filter-suggestions", to: "orgs/security_center/secret_scanning#alerts_get_filter_input_suggestions", as: :security_center_alerts_secret_scanning_get_filter_input_suggestions
    org.get     "/security/alerts/code-scanning", to: "orgs/security_center/code_scanning#index", as: :security_center_alerts_code_scanning
    org.get     "/security/alerts/code-scanning/repository-list", to: "orgs/security_center/code_scanning#repository_list", as: :security_center_code_scanning_repository_list
    org.get     "/security/alerts/code-scanning/tool-list", to: "orgs/security_center/code_scanning#tool_list", as: :security_center_code_scanning_tool_list
    org.get     "/security/alerts/code-scanning/rule-list", to: "orgs/security_center/code_scanning#rule_list", as: :security_center_code_scanning_rule_list
    org.get     "/security/alerts/code-scanning/severity-list", to: "orgs/security_center/code_scanning#severity_list", as: :security_center_code_scanning_severity_list
    org.get     "/security/alerts/code-scanning/tag-list", to: "orgs/security_center/code_scanning#tag_list", as: :security_center_code_scanning_tag_list
    org.get     "/security/alerts/code-scanning/alert-list", to: "orgs/security_center/code_scanning_alerts#index", as: :security_center_code_scanning_alerts_list
    org.get     "/security/alerts/code-scanning/alert-group-list", to: "orgs/security_center/code_scanning_alert_groups#index", as: :security_center_code_scanning_alert_groups_list
    org.get     "/security/alerts/dependabot", to: "orgs/security_center/dependabot_alerts#index", as: :security_center_alerts_dependabot
    org.get     "/security/alerts/dependabot/closed-filter", to: "orgs/security_center/dependabot_alerts#closed_as_filter", as: :security_center_alerts_dependabot_closed_as_filter
    org.get     "/security/alerts/dependabot/repository-filter", to: "orgs/security_center/dependabot_alerts#repository_filter", as: :security_center_alerts_dependabot_repository_filter
    org.get     "/security/alerts/dependabot/severity-filter", to: "orgs/security_center/dependabot_alerts#severity_filter", as: :security_center_alerts_dependabot_severity_filter
    org.get     "/security/alerts/dependabot/package-filter", to: "orgs/security_center/dependabot_alerts#package_filter", as: :security_center_alerts_dependabot_package_filter
    org.get     "/security/alerts/dependabot/ecosystem-filter", to: "orgs/security_center/dependabot_alerts#ecosystem_filter", as: :security_center_alerts_dependabot_ecosystem_filter
    org.get     "/security/alerts/dependabot/filter-input-suggestions", to: "orgs/security_center/dependabot_alerts#filter_input_suggestions", as: :security_center_alerts_dependabot_filter_input_suggestions

    org.get     "/security/campaigns", to: "orgs/security_center/security_campaigns#index", as: :security_center_security_campaigns
    org.get     "/security/campaigns/new", to: "orgs/security_center/security_campaigns#new", as: :security_center_security_campaigns_new
    org.get     "/security/campaigns/drafts", to: "orgs/security_center/security_campaigns_drafts#index", as: :security_center_security_campaigns_drafts
    org.post    "/security/campaigns/drafts", to: "orgs/security_center/security_campaigns_drafts#create", as: :security_center_security_campaigns_draft_create
    org.delete  "/security/campaigns/drafts/:number", to: "orgs/security_center/security_campaigns_drafts#destroy", as: :security_center_security_campaigns_draft_delete
    org.put     "/security/campaigns/drafts/:number", to: "orgs/security_center/security_campaigns_drafts#update", as: :security_center_security_campaigns_draft_update
    org.get     "/security/campaigns/:number/publish", to: "orgs/security_center/security_campaigns_drafts_publish#show", as: :security_center_security_campaigns_drafts_publish
    org.post    "/security/campaigns/drafts/:number/publish", to: "orgs/security_center/security_campaigns_drafts_publish#create", as: :security_center_security_campaigns_draft_publish
    org.get     "/security/campaigns/publish", to: "orgs/security_center/security_campaigns_publish#show", as: :security_center_security_campaigns_publish
    org.get     "/security/campaigns/open/list", to: "orgs/security_center/open_security_campaigns_list#index", as: :security_center_open_security_campaigns_list
    org.get     "/security/campaigns/closed/list", to: "orgs/security_center/closed_security_campaigns_list#index", as: :security_center_closed_security_campaigns_list
    org.get     "/security/campaigns/managers", to: "orgs/security_center/security_campaigns_managers#index", as: :security_center_security_campaigns_managers
    org.get     "/security/campaigns/counts", to: "orgs/security_center/security_campaigns_counts#index", as: :security_center_security_campaigns_counts
    org.get     "/security/campaigns/alerts/summary", to: "orgs/security_center/security_campaigns_alerts_summary#index", as: :security_center_security_campaigns_alerts_summary
    org.post    "/security/campaigns", to: "orgs/security_center/security_campaigns#create", as: :create_security_campaigns
    org.get     "/security/campaigns/:number", to: "orgs/security_center/security_campaigns#show", as: :security_center_security_campaign
    org.put     "/security/campaigns/:number", to: "orgs/security_center/security_campaigns#update", as: :security_center_update_security_campaign
    org.delete  "/security/campaigns/:number", to: "orgs/security_center/security_campaigns#destroy", as: :security_center_destroy_security_campaign
    org.get     "/security/campaigns/:number/alerts", to: "orgs/security_center/security_campaign_alerts#index", as: :security_center_security_campaign_alerts
    org.get     "/security/campaigns/:number/repositories-summary", to: "orgs/security_center/security_campaign_repositories_summary#index", as: :security_center_security_campaign_repositories_summary
    org.get     "/security/campaigns/:number/alerts-groups", to: "orgs/security_center/security_campaign_alerts_groups#index", as: :security_center_security_campaign_alerts_groups
    org.post     "/security/campaigns/:number/close", to: "orgs/security_center/security_campaigns_close#update", as: :security_center_security_campaign_close
    org.post     "/security/campaigns/:number/reopen", to: "orgs/security_center/security_campaigns_reopen#update", as: :security_center_security_campaign_reopen

    org.get     "/teams",                 to: "orgs/teams#index", as: :teams
    org.get     "/child_teams",           to: "orgs/teams#child_teams", as: :child_teams
    org.get     "/new-team",              to: "orgs/teams#new", as: :new_team
    org.post    "/teams/_check_name",     to: "orgs/teams#check_name", as: :check_team_name
    if GitHub.enterprise?
      org.get     "/teams/group_suggestions", to: "orgs/teams#ldap_group_suggestions", as: :group_suggestions
    else
      org.get     "/teams/group_suggestions", to: "orgs/team_sync/external_groups#external_group_suggestions", as: :external_group_suggestions
    end

    org.get     "external_group_members/:slug/:id", to: redirect("/enterprises/%{slug}/external_group_members/%{id}"), as: :external_group_members

    # Manage external group team mapping
    org.get     "/teams/:team_slug/mappings", to: "orgs/team_sync/group_mappings#list_group_mappings", as: :list_group_mappings
    org.put     "/teams/set_visibility",  to: "orgs/teams#set_visibility", as: :teams_set_visibility
    org.get     "/teams/important_changes_summary", to: "orgs/teams#important_changes_summary", as: :org_teams_important_changes_summary
    org.get     "/teams/toolbar_actions", to: "orgs/teams#teams_toolbar_actions", as: :org_teams_toolbar_actions

    org.get     "/owners_team", to: "orgs/teams#owners_team", as: :org_owners_team
    org.put     "/owners_team", to: "orgs/teams#rename_owners_team", as: :org_rename_owners_team
    org.delete  "/owners_team", to: "orgs/teams#destroy_owners_team", as: :org_destroy_owners_team

    org.get     "/teams/:team_slug",                           to: "orgs/team_members#index", as: :team
    org.get     "/teams/:team_slug/hovercard",                 to: "hovercards/teams#show"
    org.get     "/teams/:team_slug/teams",                     to: "orgs/teams#teams", as: :team_teams
    org.delete  "/teams/:team_slug/teams",                     to: "orgs/teams#destroy_team_teams", as: :destroy_team_teams
    org.get     "/teams/:team_slug/edit",                      to: "orgs/teams#edit", as: :edit_team
    org.get     "/teams/:team_slug/edit/review_assignment",    to: "orgs/teams#review_assignment", as: :edit_team_review_assignment
    org.put     "/teams/:team_slug/edit/review_assignment",    to: "orgs/teams#update_review_assignment", as: :update_team_review_assignment
    org.get     "/teams/:team_slug/members_toolbar_actions",   to: "orgs/teams#members_toolbar_actions", as: :org_team_members_toolbar_actions
    org.get     "/teams/:team_slug/toolbar_actions",           to: "orgs/teams#team_teams_toolbar_actions", as: :team_teams_toolbar_actions
    org.put     "/teams/:team_slug",                           to: "orgs/teams#update"
    org.delete  "/teams/:team_slug",                           to: "orgs/teams#destroy"
    org.delete  "/teams",                                      to: "orgs/teams#destroy_teams", as: :org_destroy_teams
    org.post    "/teams",                                      to: "orgs/teams#create", as: :create_team
    org.get     "/teams_goto",                                 to: "orgs/teams#goto",   as: :goto_team
    org.get     "/team_parent_search",                         to: "orgs/teams#parent_search", as: :team_parent_search
    org.post    "/teams/:team_slug/leave",                     to: "orgs/teams#leave",  as: :leave_team
    org.put     "/teams/:team_slug/migrate_legacy_admin_team", to: "orgs/teams#migrate_legacy_admin_team", as: :migrate_legacy_admin_team
    org.get     "/teams/:team_slug/breadcrumbs",               to: "orgs/teams#team_breadcrumbs", as: :org_team_breadcrumbs
    org.put     "/teams/:team_slug/move_child",                to: "orgs/teams#move_child_team", as: :org_team_move_child_team
    org.get     "/teams/:team_slug/child_search",              to: "orgs/teams#child_search", as: :org_team_child_search
    org.put     "/teams/:team_slug/migrate_discussions",       to: "orgs/teams#migrate_discussions", as: :org_team_migrate_discussions

    # Reactions for subjects owned by teams
    org.put     "/teams/:team_slug/reactions",                 to: "reactions#update", as: :update_team_reaction, context: "team"

    resources :reminders, except: [:edit], path: "/teams/:team_slug/settings/reminders", module: [:orgs, :teams], as: :team_reminders do
      collection do
        get :repository_suggestions
      end
      member do
        post :reminder_test
      end
    end

    scope "/teams/:team_slug", module: [:orgs, :team_discussions], as: :team_discussions do
      resources :selected_repositories, only: :index do
        collection do
          resource :transfer_button, only: :show
        end
      end
    end

    # Org-level Discussions
    draw :org_level_discussions

    # The following are the upcoming new team discussion routes
    org.get     "/teams/:team_slug/posts",            to: "orgs/team_discussions#index", as: :team_posts
    org.get     "/teams/:team_slug/posts/:number",    to: "orgs/team_discussions#show", as: :team_post
    org.post    "/teams/:team_slug/posts",            to: "orgs/team_discussions#create"
    org.put     "/teams/:team_slug/posts/:number",    to: "orgs/team_discussions#update"
    org.delete  "/teams/:team_slug/posts/:number",    to: "orgs/team_discussions#destroy"

    # The following team discussion routes will soon be deprecated
    org.get     "/teams/:team_slug/discussions",            to: "orgs/team_discussions#index", as: :team_discussions
    org.get     "/teams/:team_slug/discussions/:number",    to: "orgs/team_discussions#show", as: :team_discussion
    org.post    "/teams/:team_slug/discussions",            to: "orgs/team_discussions#create"
    org.put     "/teams/:team_slug/discussions/:number",    to: "orgs/team_discussions#update"
    org.delete  "/teams/:team_slug/discussions/:number",    to: "orgs/team_discussions#destroy"

    org.post  "/teams/dismiss_teams_banner", to: "orgs/teams#dismiss_org_teams_banner", as: :org_teams_dismiss_teams_banner

    org.get   "/teams/:team_slug/repositories",                       to: "orgs/team_repositories#index", as: :team_repositories
    org.get   "/teams/:team_slug/repositories/suggestions",           to: "orgs/team_repositories#suggestions", as: :team_repository_suggestions
    org.post  "/teams/:team_slug/repositories",                       to: "orgs/team_repositories#create"
    org.put   "/teams/:team_slug/repositories/:repository_id",        to: "orgs/team_repositories#update", as: :team_repository
    org.get   "/teams/:team_slug/repositories_toolbar_actions",       to: "orgs/teams#repositories_toolbar_actions", as: :org_team_repositories_toolbar_actions
    org.post  "/teams/:team_slug/repositories/remove",                to: "orgs/team_repositories#bulk_remove", as: :team_repository_bulk_remove
    org.get   "/teams/:team_slug/repositories/accessible_to_members", to: "orgs/team_repositories#accessible_to_members", as: :org_team_repositories_accessible_to_members

    org.get "/teams/:team_slug/projects", to: redirect(status: 307) { |params, request|
      new_params = request.query_parameters.except(:type)
      "/orgs/#{params[:org]}/teams/#{params[:team_slug]}/projects#{new_params.empty? ? "" : "?#{new_params.to_param}"}"
    }, as: false, constraints: -> (request) { %w[beta new].include?(request.query_parameters[:type]) }
    org.get "/teams/:team_slug/projects", to: "orgs/team_projects#index", as: :team_projects, constraints: lambda { |request| request.query_parameters[:type] == "classic" }
    org.get "/teams/:team_slug/projects", to: "orgs/team_memexes#index", as: :team_projects_beta
    org.get "/teams/:team_slug/projects/beta/suggestions", to: "orgs/team_memexes#projects_suggestions", as: :team_project_beta_suggestions
    org.put "/teams/:team_slug/projects/beta/update", to: "orgs/team_memexes#update_project_links", as: :update_links_team_project_beta
    org.put "/teams/:team_slug/projects/beta/upsert", to: "orgs/team_memexes#upsert_team_project", as: :upsert_team_project_beta

    org.post "/teams/:team_slug/projects", to: "orgs/team_projects#create"
    org.get "/teams/:team_slug/projects/suggestions", to: "orgs/team_projects#suggestions", as: :team_project_suggestions
    org.put "/teams/:team_slug/projects/:project_id", to: "orgs/team_projects#update", as: :team_project
    org.delete "/teams/:team_slug/projects/:project_id", to: "orgs/team_projects#destroy"

    org.get     "/teams/:team_slug/members",                         to: "orgs/team_members#index", as: :team_members
    org.post    "/teams/:team_slug/members",                         to: "orgs/team_members#create"
    org.get     "/teams/:team_slug/members/suggestions",             to: "orgs/team_members#suggestions", as: :team_member_suggestions
    org.delete  "/teams/:team_slug/members/destroy",                 to: "orgs/team_members#destroy", as: :destroy_team_member
    org.put     "/teams/:team_slug/members/set_role",                to: "orgs/team_members#set_role", as: :team_set_role
    org.put     "/teams/:team_slug/members/set_maintainer",          to: "orgs/team_members#set_maintainer", as: :team_set_maintainer
    org.put     "/teams/:team_slug/members/migrate_to_collaborator", to: "orgs/team_members#migrate_to_collaborator", as: :team_members_migrate_to_collaborator
    org.get     "/teams/:team_slug/members/archived_team_posts",     to: "orgs/team_members#archived_team_posts", as: :archived_team_posts

    org.post    "/teams/:team_slug/membership_requests",         to: "orgs/team_membership_requests#create", as: :team_membership_requests
    org.delete  "/teams/:team_slug/membership_requests/cancel",  to: "orgs/team_membership_requests#destroy", as: :destroy_team_membership_request
    org.post    "/teams/:team_slug/membership_requests/approve", to: "orgs/team_membership_requests#approve", as: :approve_team_membership_request
    org.post    "/teams/:team_slug/membership_requests/deny",    to: "orgs/team_membership_requests#deny", as: :deny_team_membership_request

    org.post    "/teams/change_parent_requests/:id/approve",     to: "orgs/team_change_parent_requests#approve", as: :approve_team_change_parent_request
    org.delete  "/teams/change_parent_requests/:id/cancel",      to: "orgs/team_change_parent_requests#cancel",  as: :cancel_team_change_parent_request

    org.get  "/audit-log/export", to: "orgs/audit_log_export#show", as: :org_audit_log_export
    org.get  "/audit-log/export_status", to: "orgs/audit_log_export#export_status", as: :org_audit_log_export_status
    org.post "/audit-log/export(.:format)", to: "orgs/audit_log_export#create", as: :org_audit_log_export_create

    org.get  "/audit-log/event_settings",  to: "orgs/audit_log_event_settings#show", as: :org_audit_log_event_settings
    org.put  "/audit-log/event_settings/toggle",  to: "orgs/audit_log_event_settings#update", as: :org_audit_log_event_settings_update

    org.get  "/audit-log/export-git", to: "orgs/audit_log_git_event_export#show", as: :org_audit_log_git_event_export
    org.post "/audit-log/export-git(.:format)", to: "orgs/audit_log_git_event_export#create"
    org.get  "/audit-log/export-git-status", to: "orgs/audit_log_git_event_export#status", as: :org_audit_log_git_event_export_status

    org.get  "/members/export", to: "orgs/organization_members_export#show", as: :org_members_export
    org.post "/members/export(.:format)", to: "orgs/organization_members_export#create"

    org.post "/invitations/member_adder_add", to: "orgs/invitations/edit_redirection#create", as: :org_invitations_member_adder_add
    org.get "/invitations/via_email", to: "orgs/invitations#edit", as: :org_edit_email_invitation
    org.get "/invitations/:invitee_login/edit", to: "orgs/invitations#edit", as: :org_edit_invitation

    org.get "/invitations/reinstate_status", to: "orgs/invitations/reinstated_status#show", as: :org_reinstate_status
    org.get "/invitations/show_reinstated", to: "orgs/invitations/reinstated#show", as: :org_show_reinstated
    org.get "/invitations/reinstate_complete", to: "orgs/invitations/reinstated_completion#show", as: :org_reinstate_complete


    org.put    "/invitations/via_email", to: "orgs/invitations#update", as: :org_email_invitation
    org.put    "/invitations/:invitee_login", to: "orgs/invitations#update", as: :org_invitation
    org.get    "/invitations/invitee_suggestions", to: "orgs/invitations/invitee_suggestions#index", as: :org_invitations_invitee_suggestions
    org.post   "/invitations/create_for_new_org", to: "orgs/invitations/for_new_org#create", as: :org_invitations_create_for_new_org
    org.post   "/invitations/bulk_create_for_new_org", to: "orgs/invitations/bulk_for_new_org#create", as: :bulk_org_invitations_create_for_new_org
    org.get    "/invitations/licensing_details", to: "orgs/invitations_licensing_details#show", as: :org_invitations_licensing_details
    org.post   "/invitations", to: "orgs/invitations#create", as: :org_invitations
    org.get    "/invitation",  to: "orgs/invitations#show", as: :org_show_invitation
    org.post   "/invitation",  to: "orgs/invitations/acceptance#create", as: :org_accept_invitation
    org.delete "/invitations/:organization_invitation_id", to: "orgs/invitations#destroy", as: :destroy_org_invitation
    org.put    "/invitations/:organization_invitation_id/cancel", to: "orgs/invitations#destroy", as: :cancel_org_invitation
    org.get    "/opt-out", to: "orgs/invitations/opt_outs#new", as: :show_org_invitation_opt_out_confirmation
    org.post   "/opt-out", to: "orgs/invitations/opt_outs#create", as: :org_invitation_opt_out

    org.get "/attribution-invitations", to: "orgs/attribution_invitations#index", as: :org_attribution_invitations
    org.post "/attribution-invitations", to: "orgs/attribution_invitations#create", as: :create_org_attribution_invitation
    org.get    "/attribution-invitations/target-suggestions", to: "orgs/attribution_invitations#target_suggestions", as: :org_attribution_invitations_target_suggestions

    # SAML SSO endpoints
    org.get  "/sso",           to: "orgs/identity_management#sso",                     as: :org_idm_sso
    org.get  "/sso_status",    to: "orgs/identity_management#sso_status",              as: :org_idm_sso_status
    org.get  "/sso_modal",     to: "orgs/identity_management#sso_modal",               as: :org_idm_sso_modal
    org.get  "/sso_complete",  to: "orgs/identity_management#sso_complete",            as: :org_idm_sso_complete
    org.get  "/sso/sign_up",   to: "orgs/identity_management#sso_sign_up",             as: :org_idm_sso_sign_up
    org.get  "/saml/metadata", to: "orgs/identity_management/saml#metadata",           as: :org_idm_saml_metadata
    org.post "/saml/initiate", to: "orgs/identity_management/saml#initiate",           as: :org_idm_saml_initiate
    org.post "/saml/consume",  to: "orgs/identity_management/saml#consume",            as: :org_idm_saml_consume
    org.post "/saml/continue", to: "orgs/identity_management/saml#continue",           as: :org_idm_saml_continue
    org.get  "/saml/recover",  to: "orgs/identity_management/saml#recover_prompt",     as: :org_idm_saml_recover
    org.post "/saml/recover",  to: "orgs/identity_management/saml#recover"
    org.delete "/saml/revoke", to: "orgs/identity_management/saml#revoke",             as: :org_idm_saml_revoke

    # team synchronization endpoints
    org.post "/team-sync/install", to: "orgs/team_sync#install", as: :team_sync_install
    org.post "/team-sync/okta_install", to: "orgs/team_sync#okta_install", as: :team_sync_okta_install
    org.get  "/team-sync/setup",          to: "orgs/team_sync#setup",                      as: :team_sync_setup
    org.post "/team-sync/initiate", to: "orgs/team_sync#initiate",             as: :team_sync_initiate
    org.get  "/team-sync/review",         to: "orgs/team_sync#review",  as: :team_sync_review
    org.post "/team-sync/approve", to: "orgs/team_sync#approve", as: :team_sync_approve
    org.delete "/team-sync/cancel", to: "orgs/team_sync#cancel", as: :team_sync_cancel
    org.delete "/team-sync/disable", to: "orgs/team_sync#disable", as: :team_sync_disable
    org.put "/team-sync/update", to: "orgs/team_sync#update", as: :team_sync_update
    org.get "/custom_roles/repository_permissions", to: "orgs/autocomplete/repository_permissions#index", as: :autocomplete_repository_permissions

    org.namespace :orgs do
      namespace :team_sync do
        resource :okta_credentials, only: [:new, :create, :edit, :update]
      end
    end

    org.delete "/dismiss_notice", to: "orgs/displayed_notices#destroy", as: :dismiss_org_notice

    org.resources :insights, only: [:index], module: :orgs, as: :org_insights do
      collection do
        if GitHub.dependency_graph_enabled?
          get :dependencies, controller: :package_dependencies, action: :package_dependencies_index, as: :packages_dashboard
          get "dependencies/graphs/security", controller: :package_dependencies, action: :package_dependencies_security_graph, as: :packages_dashboard_security_graph
          get "dependencies/graphs/licenses", controller: :package_dependencies, action: :package_dependencies_licenses_graph, as: :packages_dashboard_licenses_graph
          get "dependencies/license_menu_content", controller: :package_dependencies, action: :package_dependencies_license_menu_content, as: :packages_dashboard_license_menu_content
        end
        get :api, controller: :"api_insights/summary", action: :index
        get "api/users/:user", controller: :"api_insights/users", action: :index, as: :users_api
        get "api/installations/:installation_id", controller: :"api_insights/installations", action: :index, as: :installations_api
        get "api/users/:user/actors/:actor_type/:actor_id", controller: :"api_insights/actors", action: :index, as: :actors_api
        get "org_metrics", action: :ospo_metrics
        post "org_activity_metrics", action: :ospo_activity_metrics, format: "json"
        get :repositories, action: :get_org_repos, as: :get_repos
        put :update_repositories, action: :update_org_repos, as: :update_repos
        post "org_issue_trend_data", action: :ospo_issue_trend_data, format: "json"
        post "org_issue_ttr_data", action: :ospo_issue_ttr_data, format: "json"
        post "org_pr_trend_data", action: :ospo_pr_trend_data, format: "json"

        get :metrics, controller: :copilot_metrics_insights, action: :index, as: :copilot_metrics_insights_catalog
        get "metrics/copilot-user-onboarding", controller: :copilot_metrics_insights, action: :copilot_metrics_insights_user_onboarding, as: :copilot_user_onboarding
        get "metrics/copilot-code-completions-acceptance-rate", controller: :copilot_metrics_insights, action: :copilot_metrics_insights_code_completions_acceptance_rate, as: :copilot_code_completions_acceptance_rate
        get "metrics/copilot-generated-code-acceptance-rate", controller: :copilot_metrics_insights, action: :copilot_metrics_insights_generated_code_acceptance_rate, as: :copilot_generated_code_acceptance_rate
        get "metrics/average-pull-requests-merged-per-developer", controller: :copilot_metrics_insights, action: :copilot_metrics_insights_average_pull_requests_merged_per_developer, as: :average_pull_requests_merged_per_developer
        get "metrics/average-commits-per-developer", controller: :copilot_metrics_insights, action: :copilot_metrics_insights_average_commits_per_developer, as: :average_commits_per_developer
        get "metrics/pull-request-lead-time", controller: :copilot_metrics_insights, action: :copilot_metrics_insights_pull_request_lead_time, as: :pull_request_lead_time
      end
    end

    # Actions Metrics: Actions Usage Metrics/Actions Performance Metrics
    org.scope "/actions/metrics" do
      # Usage
      org.resource :usage, only: :show, controller: "orgs/actions_metrics/usage", as: :actions_usage_metrics
      org.post :usage, action: :index, only: :index, controller: "orgs/actions_metrics/usage"
      org.post "usage/export", action: :export, only: :export, controller: "orgs/actions_metrics/usage"
      org.post "usage/export_status", action: :export_status, only: :export_status, controller: "orgs/actions_metrics/usage"
      org.get "usage/repositories", action: :repositories, only: :repositories, controller: "orgs/actions_metrics/usage"
      org.get "usage/workflows", action: :workflows, only: :workflows, controller: "orgs/actions_metrics/usage"
      org.get "usage/jobs", action: :jobs, only: :jobs, controller: "orgs/actions_metrics/usage"
      org.get "usage/runner_labels", action: :runner_labels, only: :runner_labels, controller: "orgs/actions_metrics/usage"
      org.post "usage/summary", action: :summary, only: :summary, controller: "orgs/actions_metrics/usage"

      # Performance
      org.resource :performance, only: :show, controller: "orgs/actions_metrics/performance", as: :actions_performance_metrics
      org.post :performance, action: :index, only: :index, controller: "orgs/actions_metrics/performance"
      org.post "performance/export", action: :export, only: :export, controller: "orgs/actions_metrics/performance"
      org.post "performance/export_status", action: :export_status, only: :export_status, controller: "orgs/actions_metrics/performance"
      org.get "performance/repositories", action: :repositories, only: :repositories, controller: "orgs/actions_metrics/performance"
      org.get "performance/workflows", action: :workflows, only: :workflows, controller: "orgs/actions_metrics/performance"
      org.get "performance/jobs", action: :jobs, only: :jobs, controller: "orgs/actions_metrics/performance"
      org.get "performance/runner_labels", action: :runner_labels, only: :runner_labels, controller: "orgs/actions_metrics/performance"
      org.post "performance/summary", action: :summary, only: :summary, controller: "orgs/actions_metrics/performance"
    end

    # Organization domain verification
    org.resources :domain, only: [:new, :create, :destroy], controller: "verifiable_domains", as: :org_domains do
      member do
        get :verification_steps, to: "verifiable_domains/verifications#show"
        put :regenerate_token, to: "verifiable_domains/tokens#update"
        put :verify, to: "verifiable_domains/verifications#update"
        put :approve, to: "verifiable_domains/approvals#update"
      end
    end

    org.resource :notification_restrictions,
      as: :org_notification_restrictions,
      controller: "notification_restrictions",
      only: %i(show update)

    org.resource :licensing_headroom, only: :show, controller: "orgs/licensing_headroom", as: :org_licensing_headroom

    org.post "/archive", to: "orgs/archive#create", as: :archive_org, module: :orgs
    org.delete "/unarchive", to: "orgs/archive#destroy", as: :unarchive_org, module: :orgs

    org.get "/onboarding_tasks", to: "orgs/onboarding#index", as: :org_onboarding_tasks
    org.post "/reset_onboarding_notice", to: "orgs/onboarding#update", as: :reset_org_onboarding_notice

    org.resource :member_feature_request, only: [:create, :destroy], module: :orgs, as: :org_member_feature_requests

    namespace :move_work, as: :org_move_work do
      resource :choose_resources, only: [:create]
      resource :choose_organization, only: [:new, :create]
      resource :confirmation, only: [:new, :create]
      resources :repositories, only: [:index]
      resources :projects, only: [:index]
      resources :memex_projects, only: [:index]

      get  "/new", to: "choose_resources#new"
    end

    namespace :ghas_trial do
      resources :requests, only: [:index, :create] do
        get "success", on: :collection
      end
    end

    namespace :organization_onboarding do
      resources :demo_repositories, only: [:create]
      resource :show_tasks, only: [:update]
      resource :tasks, only: [:update]
      resource :advanced_security, only: [:show], controller: :advanced_security
      resource :trial_banner, only: [:show], controller: :trial_banner
    end
  end

  namespace :growth do
    resources :notice_dismissals, only: [:create]
    resources :member_feature_request_dismissals, only: [:update]
  end

  post "/users/password", to: "users#password_check", as: :password_check

  # User routes
  scope "/users/:user_id", constraints: { user_id: USERID_REGEX } do

    ##
    # User Hovercards
    get "hovercard", to: "hovercards/users#show"

    ##
    # Achievements

    # Arctic code vault badge
    get "/acv/hovercard", to: "hovercards/acv_badges#show"
    # Profile Highlights
    get "/profile_highlights/:highlight_type/hovercard", to: "hovercards/profile_highlights#show"
    # Achievements
    get "/achievements", to: redirect("/%{user_id}?tab=achievements"), as: :user_achievements
    get "/achievements/:achievable_slug", to: redirect("/%{user_id}?tab=achievements&achievement=%{achievable_slug}"), as: :user_achievement
    get "/achievements/:achievable_slug/detail", to: "profiles/achievements#show", as: :user_achievement_detail

    resources :achievements, module: :profiles, param: :slug do
      resource :visibility, module: :achievements, only: [:create, :destroy]
    end

    # Memexes

    # Scoped to a single memex
    # New routes for ajax requests for a memex should be added here.
    scope "/projects/beta/:memex_number" do
      user_memex = self

      user_memex.put       "/", to: "users/memexes#update", as: :update_user_memex
      user_memex.delete    "/", to: "users/memexes#delete", as: :delete_user_memex
      user_memex.post      "/_stats",                       to: "users/memexes#stats", as: :user_memex_stats
      user_memex.post      "/copy",                         to: "users/memexes#copy",  as: :copy_user_memex
      user_memex.get       "/refresh",                      to: "users/memexes#refresh", as: :refresh_user_memex
      user_memex.delete    "/remove_visited",               to: "users/memexes#remove_visited", as: :remove_visited_user_memex
      user_memex.post      "/mwl_beta_signup",              to: "users/memexes#memex_without_limits_beta_signup", as: :user_memex_without_limits_beta_signup
      user_memex.post      "/dismiss_notice",               to: "users/memexes#dismiss_notice", as: :user_memex_dismiss_notice

      user_memex.get       "/filter_suggestions",           to: "users/memexes#filter_suggestions", as: :user_memex_filter_suggestions
    end

    post "projects", to: "users/memexes#create", as: :create_user_project_beta, constraints: lambda { |request| request.query_parameters[:type] == "beta" || request.query_parameters[:type] == "new"  }

    # AJAX requests that may reference an individual memex via params
    get    "projects/beta/search/repositories",          to: "users/memexes#search_repositories", as: :user_memex_search_repositories
    get    "projects/beta/search/issues_and_pulls",      to: "users/memexes#search_issues_and_pulls", as: :user_memex_search_issues_and_pulls
    get    "projects/beta/suggestions/repositories",     to: "users/memexes#suggested_repositories", as: :user_memex_suggested_repositories
    get    "projects/beta/count/issues_and_pulls",       to: "users/memexes#count_issues_and_pulls", as: :user_memex_count_issues_and_pulls

    get "projects", to: "users/projects#index", as: :user_projects, constraints: -> (request) { %w[beta classic new].include?(request.query_parameters[:type]) }
    get "projects", to: redirect(status: 307) { |params, request|
      new_params = { tab: "projects" }.merge(request.query_parameters)
      "/#{params[:user_id]}?#{new_params.to_param}"
    }, as: false

    get "projects/new/linkable_repositories", to: "users/projects#linkable_repositories", as: :new_user_project_linkable_repositories
    get "projects/:memex_number(/views/:view_number)", to: "users/memexes#show", constraints: user_memex_exists_constraint, as: :show_user_memex
    get "projects/:memex_number/assets/:user/:guid", to: "users/memexes_assets#show", as: :user_memex_assets, format: false, constraints: user_memex_exists_constraint
    get "projects/:memex_number/insights(/:chart_number)", to: "users/memexes#show", constraints: user_memex_exists_constraint, defaults: { insights: true }
    get "projects/:memex_number/*paths", to: "users/memexes#show", constraints: user_memex_exists_constraint
    get "projects/:number", to: "users/projects#show", as: :user_project
    put "projects/:number", to: "users/projects#update"
    delete "projects", to: "users/projects#destroy"
    put "projects/:number/state", to: "users/projects#update_state", as: :update_user_project_state
    post "projects/:number/clone", to: "users/projects#clone", as: :user_project_clone
    get "projects/:number/edit", to: "users/projects#edit", as: :edit_user_project
    post "projects/:number/migrate", to: "users/projects#migrate", as: :user_project_migrate
    get "projects/:number/search_results", to: "users/projects#search_results", as: :user_project_search_results
    get "projects/:number/linkable_repositories", to: "users/projects#linkable_repositories"
    get "projects/:number/repository_results", to: "users/projects#repository_results", as: :user_project_repository_results
    get "projects/:number/target_owner_results", to: "users/projects#target_owner_results", as: :user_project_target_owner_results
    get "projects/:number/add_cards_link", to: "users/projects#add_cards_link", as: :user_project_add_cards_link
    get "projects/:number/activity", to: "users/projects#activity", as: :user_project_activity
    delete "projects/:number/dismiss_notice", to: "users/projects#dismiss_notice", as: :user_dismiss_project_notice
    get  "projects/:number/migration_status", to: "users/projects#migration_status_notice_partial", as: :user_project_migration_status_notice_partial

    # Feature preview
    get    "feature_previews",                     to: "feature_preview#index",    as: :feature_previews
    get    "feature_preview/indicator_check",      to: "feature_preview#indicator_check"
    patch  "feature_preview/:feature_id/enroll",   to: "feature_preview#enroll",   as: :feature_previews_enroll
    patch  "feature_preview/:feature_id/unenroll", to: "feature_preview#unenroll", as: :feature_previews_unenroll

    # User Menu in the site header
    get "menu", to: "users#user_profile_menu"
    get "render-user-partial",       to: "users#render_user_partial", as: :render_user_partial

    post "config-repo/profile-readme-opt-in", to: "users/configuration_repositories#post_profile_readme_opt_in", as: :post_profile_readme_opt_in

    resource :profile_readme, module: :users, only: [:create]

    put "/pulls/settings/file_tree_visibility", to: "settings/file_tree_visibility#update", as: :pr_file_tree_visibility_setting

    put "/profile_feed/settings/feed_visibility", to: "settings/profile_feed_visibility#update", as: :profile_feed_visibility_setting

    put "/copilot_chat/settings/copilot_chat_visibility", to: "settings/copilot_chat_visibility#update", as: :copilot_chat_visibility_setting

    # TODO remove as part of https://github.com/github/pull-requests/issues/15546
    put "/diffs/settings/line_spacing", to: "settings/diff_line_spacing#update", as: :diffs_line_spacing_setting
  end

  # Security Center survey
  delete "/users/security_center/survey", to: "users/security_center/survey#destroy", as: :dismiss_user_security_center_survey

  delete "/orgs/:organization_id/security_center/security_configs_banner", to: "orgs/security_center/security_configs_banner#destroy", as: :dismiss_security_configs_banner

  # Enterprises
  draw :enterprises

  ##
  # PublicKeys controller
  post   "/account/public_keys",                         to: "public_keys#create",  as: :public_keys
  put    "/account/public_keys/:id",                     to: "public_keys#update",  as: :public_key,                                                             id: /[^\/.?]+/
  delete "/account/public_keys/:id",                     to: "public_keys#destroy",                                                                                 id: /[^\/.?]+/
  post   "/account/public_keys/:id/verify",              to: "public_keys#verify",  as: :verify_public_key,                                                      id: /[^\/.?]+/
  delete "/account/public_keys/:id/authorizations/:org", to: "public_keys#remove_authorization", as: :public_key_authorization,                                  id: /[^\/.?]+/

  ##
  # GitSigningSshPublicKeysController
  delete "/account/git_signing_ssh_public_keys/:id",         to: "git_signing_ssh_public_keys#destroy", as: :git_signing_ssh_public_key, id: /[^\/.?]+/

  ##
  # GpgKeysController
  post   "/account/gpg_keys",                         to: "gpg_keys#create",  as: :gpg_keys
  delete "/account/gpg_keys/:id",                     to: "gpg_keys#destroy", as: :gpg_key

  if GitHub.billing_enabled?
    # Serve the Billing webhooks endpoints
    match "/billing/stripe/platform/general", via: :all, to: GitHub::Stripe::WebhooksApp
    match "/billing/stripe/platform", via: :all, to: GitHub::Stripe::WebhooksApp
    match "/billing/stripe/connect", via: :all, to: GitHub::Stripe::WebhooksApp
    post "/billing/zuora", to: "zuora/webhooks#create"

    # CouponsController
    get  "/redeem/",       to: "coupons#find",  as: "find_coupon"
    get  "/redeem/:code",  to: "coupons#show",  as: "redeem_coupon"
    post "/redeem/:code",  to: "coupons#redeem"
    get  "/coupon/:code",  to: redirect("/redeem/%{code}")
    get  "/coupons/:code", to: redirect("/redeem/%{code}")
    get  "/$/:code",       to: redirect("/redeem/%{code}")
    get  "/business/try",  to: "coupons#business_try"

    get  "/golden_ticket/:code",   to: redirect("redeem/%{code}")
    get  "/golden_ticket_confirm", to: redirect("redeem/%{code}")

    # BillingUpgradeController
    get "/upgrading", to: "billing_upgrade#index", as: "upgrading"

    # AssetStatusController
    get  "/account/billing/data/upgrade",                          to: "asset_status#upgrade",   as: "billing_upgrade_data_plan"
    get  "/account/billing/data/downgrade",                        to: "asset_status#downgrade", as: "billing_downgrade_data_plan"
    put  "/account/billing/data",                                  to: "asset_status#update",    as: "billing_data_plan"
    get  "/organizations/:organization_id/billing/data/upgrade",   to: "asset_status#upgrade",   as: "org_billing_upgrade_data_plan",   target: "organization"
    get  "/organizations/:organization_id/billing/data/downgrade", to: "asset_status#downgrade", as: "org_billing_downgrade_data_plan", target: "organization"
    put  "/organizations/:organization_id/billing/data",           to: "asset_status#update",    as: "org_billing_data_plan",           target: "organization"

    # BillingSettingsController
    post "/billing/extra",                                             to: "billing_settings#extra_update",          as: "billing_extra_update"
    post "/account/billing/update_credit_card",                        to: "billing_settings#update_credit_card",    as: "update_credit_card"
    get  "/account/billing/client_token",                              to: "billing_settings#client_token",          as: "client_token"
    get  "/account/billing/history",                                   to: "billing_settings#payment_history",       as: "payment_history"
    get  "/account/receipt/:id",                                       to: "billing_settings#receipt",               as: "receipt"
    post "/account/cc_update",                                         to: "billing_settings#cc_update",             as: "cc_update"
    get  "/account/user_profile_view",                                 to: "billing_settings#user_profile_view",     as: "user_profile_view"
    post "/account/trade_screening_record_update",                     to: "billing_settings#update_trade_screening_record", as: "trade_screening_record_update"
    delete "/account/remove_billing_information",                      to: "billing_settings#remove_billing_information", as: "remove_billing_information"
    put "/account/unlink_trade_screening_record_from_org",             to: "billing_settings#unlink_trade_screening_record_from_org", as: "unlink_trade_screening_record_from_org"
    post "/account/billing_update",                                    to: "billing_settings#billing_update",        as: "billing_update"
    post "/account/cycle_update",                                      to: "billing_settings#cycle_update",          as: "cycle_update"
    get  "/account/plans",                                             to: "billing_settings#plans",                 as: "plans"
    get  "/account/upgrade",                                           to: "billing_settings#upgrade",               as: "upgrade"
    post "/account/downgrade_with_exit_survey",                        to: "billing_settings#downgrade_with_exit_survey", as: "downgrade_with_exit_survey"
    get  "/organizations/:organization_id/billing/receipt/:id",        to: "billing_settings#receipt",            as: "org_receipt",            target: "organization"
    get  "/organizations/:organization_id/billing/plans",              to: "billing_settings#plans",              as: "org_plans",              target: "organization"
    post "/organizations/:organization_id/billing/cc_update",          to: "billing_settings#cc_update",          as: "org_cc_update",          target: "organization"
    post "/organizations/:organization_id/billing/cycle_update",       to: "billing_settings#cycle_update",       as: "org_cycle_update",       target: "organization"
    post "/organizations/:organization_id/billing/extra",              to: "billing_settings#extra_update",       as: "org_extra_update",       target: "organization"
    get  "/organizations/:organization_id/billing/history",            to: "billing_settings#payment_history",    as: "org_payment_history",    target: "organization"
    post "/organizations/:organization_id/billing/update_credit_card", to: "billing_settings#update_credit_card", as: "org_update_credit_card", target: "organization"
    put  "/organizations/:organization_id/billing/update_email",       to: "billing_settings#update_email",       as: "update_billing_email",   target: "organization"
    post "/organizations/:organization_id/billing/downgrade_with_exit_survey", to: "billing_settings#downgrade_with_exit_survey", as: "org_downgrade_with_exit_survey", target: "organization"
    get  "/account/downgrade/features_count",                          to: "billing_settings#downgrade_features_count",     as: "billing_downgrade_features_count"
    get "/settings/billing/subscription_items/:subscription_item_id/change_duration",    to: "subscription_items#preview_change_duration", as: "subscription_item_change_duration"
    put "/settings/billing/subscription_items/:subscription_item_id/change_duration",   to: "subscription_items#update_duration"

    get  "/account/billing/metered_exports/:id", to: "settings/metered_exports#show",    as: "metered_export"
    post "/account/billing/metered_exports",     to: "settings/metered_exports#create",  as: "metered_exports"
    post "/organizations/:organization_id/billing/metered_exports",     to: "settings/metered_exports#create",      as: "org_metered_exports",        target: "organization"
    get  "/organizations/:organization_id/billing/metered_exports/:id", to: "settings/metered_exports#show",        as: "org_metered_export",         target: "organization"

    get "/businesses/:business_id/billing/receipt/:id",                to: "billing_settings#receipt",            as: "business_receipt",        target: "business"

    # BillingSetting::ContactsController
    resource :contact, only: [:create, :update, :destroy], module: "billing_settings", as: "billing_contact", path: "/account/contact"
    resource :contact_link, only: [:create, :destroy], module: "billing_settings", as: "billing_contact_link", path: "/account/contact_link"
    resource :contact_stash, only: [:create], module: "billing_settings", as: "stash_contact", path: "/account/stash_contact"

    # BillingExternalEmailsController
    put  "/organizations/:organization_id/billing_external_emails/update_primary", to: "billing_external_emails#update_primary", as: "billing_update_primary_email",  target: "organization"
    post  "/organizations/:organization_id/billing_external_emails/create",        to: "billing_external_emails#create",         as: "billing_create_external_email", target: "organization"
    post  "/organizations/:organization_id/billing_external_emails/mark_primary/:id",  to: "billing_external_emails#mark_primary",   as: "billing_mark_primary_email",    target: "organization"
    delete  "/organizations/:organization_id/billing_external_emails/delete/:id",  to: "billing_external_emails#delete",         as: "billing_delete_external_email", target: "organization"

    # BillingManagersController
    get  "/organizations/:organization_id/billing_managers/new",                   to: "billing_managers#new",                 as: "org_new_billing_manager"
    post "/organizations/:organization_id/billing_managers",                       to: "billing_managers#create",              as: "org_billing_managers"
    get  "/organizations/:organization_id/billing_managers/invitation",            to: "billing_managers#show_pending",        as: "org_show_pending_billing_manager_invitation"
    get  "/organizations/:organization_id/billing_managers/invitation/sign_up",    to: "billing_managers#sign_up",             as: "org_sign_up_billing_manager_invitation"
    delete  "/organizations/:organization_id/billing_managers/invitation/:id",     to: "billing_managers#cancel",              as: "org_billing_manager_invitation", constraints: { id: /.*/ }
    post "/organizations/:organization_id/billing_managers/accept",                to: "billing_managers#accept",              as: "org_accept_billing_manager_invitation"
    delete "/organizations/:organization_id/billing_managers/:id",                 to: "billing_managers#destroy",             as: "org_billing_manager"
    get    "/organizations/:organization_id/billing_managers/invitee_suggestions", to: "billing_managers#invitee_suggestions", as: "org_billing_manager_suggestions"
    post "/organizations/:organization_id/billing_managers/invitation/:id/resend", to: "billing_managers#resend_invitation",   as: "org_resend_billing_manager_invitation", constraints: { id: /.*/ }

    # BillingController
    delete "/stafftools/enterprises/:slug/billing/unlink_zuora", to: "stafftools/businesses/billing/zuora_accounts#destroy", as: "stafftools_business_zuora_account"

    # SelfServeInvoiceController
    put "/users/:user_id/self_serve_invoicing", to: "billing_settings/self_serve_invoice#update", as: :billing_self_serve_invoicing
    put "/organizations/:organization_id/self_serve_invoicing", to: "billing_settings/self_serve_invoice#update", as: :org_self_serve_invoicing
    put "/businesses/:slug/self_serve_invoicing", to: "billing_settings/self_serve_invoice#update", as: :business_self_serve_invoicing

    # InvoicesDownloadController
    get "/users/:user_id/billing/invoices/download", to: "billing_settings/invoices_download#show", as: :user_billing_download_invoices
    get "/organizations/:organization_id/billing/invoices/download", to: "billing_settings/invoices_download#show", as: :org_billing_download_invoices
    get "/businesses/:slug/billing/invoices/download", to: "billing_settings/invoices_download#show", as: :self_serve_business_billing_download_invoices

    # PendingPlanChangesController
    put "/pending_plan_changes/:id", to: "pending_plan_changes#update", as: :update_pending_plan_change
    put "/businesses/:slug/pending_plan_changes/", to: "businesses/pending_plan_changes#update", as: :business_update_pending_plan_change

    # PendingSubscriptionItemChangesController
    resources :pending_subscription_item_changes, only: [:update, :destroy] do
      member do
        resource :free_trial_cancellation, only: :update, module: :pending_subscription_item_changes, as: :pending_subscription_item_change_free_trial_cancellation
      end
    end

    resource :oauth_callback, only: [:show], module: "azure", path: "/azure/oauth_callback"
    scope module: "azure", path: "/azure/:account_type/:account_id", as: "azure", constraints: { account_type: /(enterprise|organization)/ } do
      resources :tenants, only: [:index]
      resources :subscriptions, only: [:index]
      resource :linked_subscriptions, only: [:update, :destroy]
      resource :authentications, only: [:show]
      resource :settings, only: [:update]
    end

    # Orgs::ConsumedLicensesController
    get "/organizations/:organization_id/consumed_licenses", to: "orgs/consumed_licenses#show", as: :org_consumed_licenses
  end

  # Only for enterprise managed user
  get  "/users/:user_id/billing/download_active_committers", to: "users/ghas_active_committers#download_active_committers", as: :user_download_active_committers

  get "/organizations/:organization_id/download_active_committers", to: "orgs/ghas_active_committers#download_active_committers", as: :org_download_active_committers
  get "/organizations/:organization_id/download_repository_active_committers/:repo_id", to: "orgs/ghas_active_committers#download_repository_active_committers", as: :org_download_repository_active_committers

  # BillingSettingsController routes needed for enterprise
  get  "/settings/billing/summary",                                  to: "billing_settings#user_billing",                as: :settings_user_billing
  get  "/settings/billing/lfs_bandwidth",                            to: "billing_settings#lfs_bandwidth_breakdown",     as: :settings_lfs_bandwidth_breakdown
  get  "/settings/billing/lfs_storage",                              to: "billing_settings#lfs_storage_breakdown",       as: :settings_lfs_storage_breakdown
  get  "/settings/billing/cost_management",                          to: redirect("/settings/billing/spending_limit")
  get  "/settings/billing/:tab",                                     to: "billing_settings#user_billing",       as: :settings_user_billing_tab, tab: /licensing|payment_information|spending_limit|subscriptions/
  post "/settings/billing/spending_limit",                           to: "billing_settings#spending_limit",     as: :settings_user_spending_limit
  post "/settings/billing/usage_notification_settings",              to: "billing_settings#usage_notification_settings",     as: :settings_user_usage_notification_settings
  get  "/settings/billing/plans",                                    to: "billing_settings#plans",              as: :settings_user_plans
  get "/settings/billing/download_active_committers",                to: "businesses/enterprise_licensing#download_active_committers", as: :settings_download_active_committers
  get "/settings/billing/download_maximum_committers",               to: "businesses/enterprise_licensing#download_maximum_committers", as: :settings_download_maximum_committers

  # Controllers within billing settings
  get  "/settings/billing/actions_usage",                            to: "billing_settings/shared_products_usage#show_actions",        as: :settings_user_billing_actions_usage
  get  "/settings/billing/packages_usage",                           to: "billing_settings/shared_products_usage#show_packages",       as: :settings_user_billing_packages_usage
  get  "/settings/billing/shared_storage_usage",                     to: "billing_settings/shared_products_usage#show_shared_storage", as: :settings_user_billing_storage_usage
  get  "/settings/billing/codespaces_usage",                         to: "billing_settings/codespaces_usage#show",                     as: :settings_user_billing_codespaces_usage
  get  "/settings/billing/usage_notification",                       to: "billing_settings/usage_notifications#show",                  as: :settings_user_billing_usage_notification
  post "/settings/billing/downgrade_survey",                         to: "billing_settings/downgrade_surveys#create",                  as: :settings_user_billing_downgrade_survey
  get  "/settings/billing/plan_downgrade",                           to: "billing_settings/plan_downgrade#show",                       as: :settings_user_billing_plan_downgrade

  namespace :billing do
    resource :sales_tax_exemptions, only: [:create, :destroy]

    namespace :notifications do
      resource :dismissals, only: :create
    end
  end

  if GitHub.devtools_enabled?
    draw :devtools
  end

  # Alpha signup for GitHub team synchronization
  get   "/features/team-sync/signup",  to: "team_sync_beta_memberships#signup", as: :team_sync_beta_signup

  # Beta signup for Code Scanning
  unless GitHub.enterprise?
    get "/features/security/advanced-security/signup", to: redirect("https://resources.github.com/code-scanning/")
  end

  # Auth endpoint for use by github.dev editor (FKA codespaces serverless)
  get  "/auth/github_editor", to: "codespaces/lightweight_web_editor#auth", as: "auth_github_editor"

  # Copilot
  draw :copilot

  # Copilot MCP
  draw :copilot_mcp

  # Spark
  draw :spark

  post "/copilot/completions", to: "ghost_pilot/completions#create", as: :ghost_pilot_completions
  get "/copilot/completions/token", to: "ghost_pilot/completions#token", as: :ghost_pilot_completions_token
  get "/copilot/completions/feedback/:repository_id", to: "ghost_pilot/completions#feedback", as: :ghost_pilot_completions_feedback
  get "/copilot/hovercard", to: "hovercards/copilot#show"

  get "/copilot/chat-links", to: "copilot/chat/chat_links#show", as: :copilot_chat_links
  get "/copilot/chat/reference/:owner/:name/(:type/*id)", to: "copilot/chat/repository_references#show", as: :copilot_chat_repository_reference, constraints: { id: /.+/ }

  # Copilot Chat Autocomplete Endpoints
  get "/copilot/chat/autocomplete/discussions", to: "copilot/chat/autocomplete/discussions#index"
  get "/copilot/chat/autocomplete/issues", to: "copilot/chat/autocomplete/issues#index"
  get "/copilot/chat/autocomplete/pulls", to: "copilot/chat/autocomplete/pulls#index"

  post "copilot/feedback-survey/dismiss", to: "copilot/feedback_survey#dismiss", as: :copilot_feedback_survey_dismiss
  post "copilot/feedback-survey/open",    to: "copilot/feedback_survey#open",    as: :copilot_feedback_survey_open

  # Beta signup for Merge Queue
  get   "/features/merge-queue/signup", to: "merge_queue_beta_memberships#signup",  as: :merge_queue_beta_signup

  # Redirect GitHub Actions Importer signup to public announcement blog post
  get   "/features/actions-importer/signup", to: redirect("#{GitHub.blog_url}/2023-03-01-github-actions-importer-is-now-generally-available")

  # Beta signup
  get   "/features/:beta/signup",    to: "beta_memberships#signup",    as: :beta_signup
  post  "/features/:beta/agree",     to: "beta_memberships#agree",     as: :beta_agree, format: false
  get   "/features/:beta/thanks",    to: "beta_memberships#thanks",    as: :beta_thanks, format: false

  ##
  # Biztools
  draw :biztools

  ##
  # Dashboard
  draw :dashboard

  ##
  # Stafftools
  draw :stafftools

  ##
  # gh_example_path routes
  draw :gh

  ##
  # Actions
  draw :actions

  ##
  # Kredz
  draw :kredz

  ##
  # Education
  draw :education

  # WikiController
  get  "/wiki",        to: "wiki#help_redirect", as: nil

  # Discussions Dashboard
  get "/discussions",           to: "discussions_dashboard#index", created_by: true,
    as: :all_discussions
  get "/discussions/commented", to: "discussions_dashboard#index", commented: true,
    as: :all_discussions_commented

  ##
  # Support archive
  # https://support.github.com/contact/discussions/sales/658-interest-in-githubfi
  get "/discussions/:category/:thread", to: "bounce#support_bounce"
  get "/discussions/:category",         to: "bounce#support_bounce"

  # Secret scanning alerts survey
  unless GitHub.enterprise?
    post "/secret-scanning-push-protection-survey/answer", to: "settings/push_protection/survey#answer", as: :secret_scanning_push_protection_survey_answer
    post "/secret-scanning-push-protection-survey/dismiss", to: "settings/push_protection/survey#dismiss", as: :secret_scanning_push_protection_survey_dismiss
  end

  # Dependabot updates paused banner
  post "/dependabot-updates-paused-banner/dismiss", to: "dependabot/paused_updates_dismissal#create", as: :dismiss_paused_banner

  # Package dependencies dashboard
  if GitHub.dependency_graph_enabled?
    get "/dependency-insights", to: "package_dependencies/global#index", as: :packages_dashboard
    get "/dependency-insights/graphs/security", to: "package_dependencies/global#security_graph", as: :packages_dashboard_security_graph
    get "/dependency-insights/graphs/licenses", to: "package_dependencies/global#licenses_graph", as: :packages_dashboard_licenses_graph
    get "/dependency-insights/:ecosystem/:name/:version(/:tab)", to: "package_dependencies/global#show", as: :package_details, constraints: { name: PACKAGE_DEPENDENCY_REGEX, version: PACKAGE_DEPENDENCY_REGEX }
    get "/dependency-insights/license_menu_content", to: "package_dependencies/global#license_menu_content", as: :packages_dashboard_license_menu_content
  end

  # Issues Dashboard
  get "/issues",                   to: "issues#dashboard", created_by: true, as: :all_issues
  get "/issues/assigned",          to: "issues#dashboard", assigned:   true, as: :all_issues_assigned
  get "/issues/mentioned",         to: "issues#dashboard", mentioned:  true, as: :all_issues_mentioned
  get "/issues/show_menu_content", to: "issues#show_menu_content", as: :show_menu_content_issues_dashboard

  # Ensure this comes after any /issues/* named routes as this is a catch-all
  get "/issues/:shortcut_id",  to: "issues#dashboard", as: :saved_view

  # Hyperlist web
  post "/issues",           to: "issues#dashboard", as: :issues_toggle_experience

  post "/comments/issues", to: "comments/issues#create", as: :new_issue_from_comment

  # Pull Requests Dashboard
  get "/pulls",             to: "issues#dashboard", created_by: true, pulls_only: true, as: :all_pulls
  get "/pulls/assigned",    to: "issues#dashboard", assigned:   true, pulls_only: true, as: :all_pulls_assigned
  get "/pulls/mentioned",   to: "issues#dashboard", mentioned:  true, pulls_only: true, as: :all_pulls_mentioned
  get "/pulls/review-requested", to: "issues#dashboard", review_requested:  true, pulls_only: true, as: :all_pulls_review_requested
  get "/pull/:user_id/:repository/:id/review-status", to: "issues#pr_review_status", pulls_only: true, as: :pull_review_status

  post "/upload/manifests",       to: "upload_manifests#create", as: :upload_manifests
  post "/upload/policies/:model", to: "upload_policies#create", as: :upload_policy
  put  "/upload/:model(/:id)",    to: "uploads#update"
  post "/upload/:model(/:id)",    to: "uploads#create", as: :upload

  # Projects Dashboard
  get "/projects", to: "memexes#index", as: :projects_dashboard

  ##
  # New repository
  get "/new",    to: "repositories#new", as: :new_repository
  get "/repositories/new/templates", to: "repositories#repository_templates_for_current_user", as: :repository_templates_for_current_user

  ##
  # Repository import
  get "/new/import",  to: "repository_imports#new",    as: :new_repository_import
  post "/new/import", to: "repository_imports#create", as: :repository_imports
  # For /owner/repo/import, to: "repository_imports#show" search this file for "Repository import"

  # Legacy Query Builder & Filter suggestion endpoints
  get "/filter-suggestions/users", to: "filter_suggestions#users"
  get "/filter-suggestions/labels", to: "filter_suggestions#labels"
  get "/filter-suggestions/teams", to: "filter_suggestions#teams"
  get "/filter-suggestions/projects", to: "filter_suggestions#projects"
  get "/filter-suggestions/repositories", to: "filter_suggestions/repositories#index"
  get "/filter-suggestions/languages", to: "filter_suggestions/languages#index"
  get "/filter-suggestions/milestones", to: "filter_suggestions/milestones#index"

  # Filter component suggestions & validations
  get "/_filter/issues", to: "filter_providers/issues#index"
  get "/_filter/issues/validate", to: "filter_providers/issues#show"
  get "/_filter/labels", to: "filter_providers/labels#index"
  get "/_filter/labels/validate", to: "filter_providers/labels#show"
  get "/_filter/languages", to: "filter_providers/languages#index"
  get "/_filter/languages/validate", to: "filter_providers/languages#show"
  get "/_filter/milestones", to: "filter_providers/milestones#index"
  get "/_filter/milestones/validate", to: "filter_providers/milestones#show"
  get "/_filter/projects", to: "filter_providers/projects#index"
  get "/_filter/projects/validate", to: "filter_providers/projects#show"
  get "/_filter/repositories", to: "filter_providers/repositories#index"
  get "/_filter/repositories/validate", to: "filter_providers/repositories#show"
  get "/_filter/organizations", to: "filter_providers/organizations#index"
  get "/_filter/organizations/validate", to: "filter_providers/organizations#show"
  get "/_filter/repositories", to: "filter_providers/repositories#index"
  get "/_filter/repositories/validate", to: "filter_providers/repositories#show"
  get "/_filter/teams", to: "filter_providers/teams#index"
  get "/_filter/teams/validate", to: "filter_providers/teams#show"
  get "/_filter/users", to: "filter_providers/users#index"
  get "/_filter/users/validate", to: "filter_providers/users#show"

  ## ReposPicker component
  get "/repositories/picker/definitions",  to: "repos_picker/definitions#index"
  get "/repositories/picker/search", to: "repos_picker/repositories#index"
  get "/repositories/picker/count", to: "repos_picker/repositories#count"

  ##
  # Ajax
  post "/users/follow",          to: "users/follows#create", as: :follow_user, format: false
  post "/users/unfollow",        to: "users/follows#destroy", as: :unfollow_user, format: false
  post "/users/set_protocol",    to: "users#set_protocol", as: :user_set_protocol, format: false
  get "/users/status",           to: "user_statuses#show", as: :user_status
  put "/users/status",           to: "user_statuses#update"
  get "/users/status/members",   to: "user_statuses#member_statuses", as: :member_statuses
  get "/users/status/emoji",     to: "user_statuses#emoji_picker", as: :user_status_emoji_picker
  get "/users/status/organizations", to: "user_statuses#org_picker", as: :user_status_org_picker

  # Autocomplete
  get "/autocomplete/users", to: "autocomplete/users#index",  as: :autocomplete_users
  get "/autocomplete/all-organizations", to: "autocomplete/organizations#index", as: :autocomplete_organizations
  get "/autocomplete/:org/users", to: "autocomplete/org_users#index", as: :autocomplete_org_users
  get "/autocomplete/user-suggestions", to: "autocomplete/user_suggestions#index", as: :user_suggestions
  get "/autocomplete/organizations", to: "autocomplete/organization_suggestions#index", as: :organization_suggestions
  get "/autocomplete/emoji", to: "autocomplete/emoji_suggestions#index", as: :emoji_suggestions
  get "/autocomplete/emojis_for_editor", to: "autocomplete/emojis_for_editor#index", as: :emojis_for_editor

  namespace :move_work, as: :user_move_work do
    resource :choose_resources, only: [:create]
    resource :choose_organization, only: [:new, :create]
    resource :organization do
      get "/plans", to: "organizations/plans#index", as: :plans
    end
    resource :confirmation, only: [:new, :create]
    resources :repositories, only: [:index]
    resources :projects, only: [:index]
    resources :memex_projects, only: [:index]

    get  "/new", to: "choose_resources#new"
  end

  get "/move_work/:id", as: :move_work, to: "move_work/move_work#show"

  namespace :email, format: false do
    resource :subscribe,     only: [:create, :update]
    resource :unsubscribe,   only: [:show]

    if GitHub.email_preference_center_enabled?
      resource :preferences, only: [:show, :update]
      resource :optin,       only: [:create, :show]
      get "/", to: redirect("/email/preferences")
    else
      get "/", to: redirect("/settings/email#preferences")
    end
  end
  if GitHub.email_preference_center_enabled?
    get "/email-optin", to: redirect(path: "/email/optin"),          format: false
  else
    get "/email-optin", to: redirect("/settings/email#preferences"), format: false
  end

  resource :newsletter_preferences, only: [:update]

  get "/mailers/unsubscribe",             to: redirect("/email/unsubscribe"), format: false
  get "/settings/unsubscribe/newsletter", to: redirect("/email/unsubscribe"), format: false

  get "/search",                to: "codesearch#index",           as: :search
  get "/search/advanced",       to: "codesearch#advanced_search", as: :advanced_search
  get "/search/count",          to: "codesearch#count",           as: :search_count
  get "/search/explore-topics", to: "codesearch#explore_topics",  as: :search_explore_topics
  get "/search/refresh_blackbird_caches", to: "codesearch#refresh_blackbird_caches"
  post "/search/index_embeddings", to: "codesearch#index_embeddings"
  delete "/search/index_embeddings", to: "codesearch#delete_embeddings"
  get "/search/blackbird_count", to: "codesearch#blackbird_count"
  get "/search/suggestions",    to: "codesearch#suggestions",     as: :blackbird_suggestions
  get "/search/warm_blackbird_caches", to: "codesearch#warm_blackbird_caches"
  get "/search/check_indexing_status", to: "codesearch#check_indexing_status", as: :check_indexing_status
  get "/search/custom_scopes", to: "search/custom_scopes#index"
  post "/search/custom_scopes", to: "search/custom_scopes#save"
  delete "/search/custom_scopes", to: "search/custom_scopes#destroy"
  post "/search/custom_scopes/check_name", to: "search/custom_scopes#check_name", as: :search_custom_scopes_check_name
  post "/search/feedback", to: "codesearch#feedback", as: :search_feedback
  post "/search/stats", to: "search_stats#create", as: :search_stats

  if GitHub.enterprise?
    get "/dotcom-search", to: "dotcom_codesearch#index", as: :dotcom_search
    get "/dotcom-search/advanced", to: "dotcom_codesearch/advanced#index", as: :dotcom_advanced_search
    get "/dotcom-search/count", to: "dotcom_codesearch#count", as: :dotcom_search_count
  end

  # CommandPalette::ProvidersController
  get "/command_palette/:provider", to: "command_palette/providers#index", as: :command_palette_provider
  post "/command_palette/command", to: "command_palette/commands#execute", as: :command_palette_command

  # NotificationsController

  # get redirects from v2 -> beta
  get  "/notifications/v2",       to: redirect(path: "/notifications/beta")
  get  "/notifications/v2/*rest", to: redirect(path: "/notifications/beta/%{rest}")

  get "/notifications/beta", to: redirect(path: "/notifications"), constraints: NOTIFICATIONS_V2_REDIRECT_CONSTRAINT, as: :notification_beta_redirect
  get "/notifications", to: "notifications_v2#index", constraints: NOTIFICATIONS_V2_REDIRECT_CONSTRAINT, as: :notifications_v2_index
  get "/notifications/all", to: redirect("/notifications"), constraints: NOTIFICATIONS_V2_REDIRECT_CONSTRAINT, as: :notifications_beta_redirect_all
  get "/notifications/read", to: redirect("/notifications?query=is%3Aread"), constraints: NOTIFICATIONS_V2_REDIRECT_CONSTRAINT, as: :notifications_beta_redirect_read
  get "/notifications/participating", to: redirect("/notifications?query=reason%3Aparticipating"), constraints: NOTIFICATIONS_V2_REDIRECT_CONSTRAINT, as: :notifications_beta_redirect_participating
  get "/notifications/saved", to: redirect("/notifications?query=is%3Asaved"), constraints: NOTIFICATIONS_V2_REDIRECT_CONSTRAINT, as: :notifications_beta_redirect_saved

  # Toggle the inbox experience with the notification_inbox feature preview
  post "/toggle_inbox", to: "notifications_v2#toggle_inbox_feature", as: :inbox_toggle_feature

  get  "/inbox",                                               to: "notifications#inbox"
  get  "/inbox/:notification_id",                              to: "notifications#inbox"
  get  "/inbox/views/:view_id",                                to: "notifications#inbox"
  get  "/notifications/beta",                                  to: "notifications_v2#index"
  get  "/notifications/beta/shelf",                            to: "notifications_v2#shelf", as: :notification_shelf
  post "/notifications/beta/set_preferred_inbox_query",        to: "notifications_v2#set_preferred_inbox_query", as: :notifications_beta_set_preferred_inbox_query
  post "/notifications/beta/update_view_preference",           to: "notifications_v2#update_view_preference", as: :notifications_beta_update_view_preference
  post "/notifications/beta/mark",                             to: "notifications_v2#mark_as_read", as: :notifications_beta_mark_as_read
  post "/notifications/beta/unmark",                           to: "notifications_v2#mark_as_unread", as: :notifications_beta_mark_as_unread
  post "/notifications/beta/archive",                          to: "notifications_v2#mark_as_archived", as: :notifications_beta_mark_as_archived
  post "/notifications/beta/unarchive",                        to: "notifications_v2#mark_as_unarchived", as: :notifications_beta_mark_as_unarchived
  post "/notifications/beta/subscribe",                        to: "notifications_v2#mark_as_subscribed", as: :notifications_beta_mark_as_subscribed
  post "/notifications/beta/unsubscribe",                      to: "notifications_v2#mark_as_unsubscribed", as: :notifications_beta_mark_as_unsubscribed
  post "/notifications/beta/star",                             to: "notifications_v2#mark_as_starred", as: :notifications_beta_mark_as_starred
  post "/notifications/beta/unstar",                           to: "notifications_v2#mark_as_unstarred", as: :notifications_beta_mark_as_unstarred
  post "/notifications/beta/create_custom_inbox",              to: "notifications_v2#create_custom_inbox", as: :notifications_beta_create_custom_inbox
  put  "/notifications/beta/update_custom_inbox",              to: "notifications_v2#update_custom_inbox", as: :notifications_beta_update_custom_inbox
  delete "/notifications/beta/delete_custom_inbox",            to: "notifications_v2#delete_custom_inbox", as: :notifications_beta_delete_custom_inbox

  # Legacy non-get routes for backwards compatibility while rolling v2 -> beta
  post "/notifications/v2/mark",                             to: "notifications_v2#mark_as_read"
  post "/notifications/v2/unmark",                           to: "notifications_v2#mark_as_unread"
  post "/notifications/v2/archive",                          to: "notifications_v2#mark_as_archived"
  post "/notifications/v2/unarchive",                        to: "notifications_v2#mark_as_unarchived"
  post "/notifications/v2/subscribe",                        to: "notifications_v2#mark_as_subscribed"
  post "/notifications/v2/unsubscribe",                      to: "notifications_v2#mark_as_unsubscribed"
  post "/notifications/v2/star",                             to: "notifications_v2#mark_as_starred"
  post "/notifications/v2/unstar",                           to: "notifications_v2#mark_as_unstarred"
  post "/notifications/v2/create_custom_inbox",              to: "notifications_v2#create_custom_inbox"
  put  "/notifications/v2/update_custom_inbox",              to: "notifications_v2#update_custom_inbox"
  delete "/notifications/v2/delete_custom_inbox",            to: "notifications_v2#delete_custom_inbox"

  get  "/notifications/beta/recent_notifications_alert",     to: "notifications_v2#recent_notifications_alert"
  get  "/notifications/beta/notifications_exist",            to: "notifications_v2#notifications_exist"
  get  "/notifications/beta/custom_inboxes_dialog",          to: "notifications_v2#custom_inboxes_dialog"
  get  "/notifications/beta/suggestions/repositories",       to: "notifications_v2#filter_suggestions", as: :notifications_beta_suggested_repositories, filter: "repositories"
  get  "/notifications/beta/suggestions/owners",             to: "notifications_v2#filter_suggestions", as: :notifications_beta_suggested_owners, filter: "owners"
  get  "/notifications/beta/suggestions/authors",            to: "notifications_v2#filter_suggestions", as: :notifications_beta_suggested_authors, filter: "authors"
  get  "/notifications/restriction_banner",                 to: "notifications_v2#notifications_restriction_banner",  as: :notifications_restriction_banner

  get  "/notifications",                                     to: "notifications#index",                      as: :notifications
  get  "/notifications/all",                                 to: "notifications#index",                      as: :all_notifications,                 all:    true
  get  "/notifications/read",                                to: "notifications#index",                      as: :read_notifications,                filter: "read"
  get  "/notifications/participating",                       to: "notifications#index",                      as: :participating_notifications,       filter: "participating"
  get  "/notifications/saved",                               to: "notifications#index",                      as: :saved_notifications,               filter: "saved"
  post "/notifications/mark",                                to: "notifications#mark_as_read",               as: :mark_notifications
  post "/notifications/unmark",                              to: "notifications#mark_as_unread",             as: :mark_notification_as_unread
  post "notifications/unwatch_repositories",                 to: "notifications#unwatch_repositories",       as: :unwatch_repositories
  post "notifications/unwatch_all",                          to: "notifications#unwatch_all",                as: :unwatch_all
  get  "/notifications/subscription",                        to: "notifications#subscription",               as: :notification_subscription
  get  "/notifications/beacon/:data.gif",                    to: "notifications#beacon",                     as: :notification_beacon
  post "/notifications/subscribe",                           to: "notifications#subscribe",                  as: :notifications_subscribe
  post "/notifications/update_subscribe",                    to: "notifications#update_subscription_status", as: :notifications_update_subscription_status
  post "/notifications/thread",                              to: "notifications#thread_subscribe",           as: :notifications_thread_subscribe
  get  "/notifications/thread_subscription",                 to: "notifications#thread_subscription",        as: :notifications_thread_subscription
  get  "/notifications/thread_subscription_dialog",          to: "notifications#thread_subscription_dialog", as: :notifications_thread_subscription_dialog
  post "/notifications/settings",                            to: "notifications#save_handlers",              as: :save_notification_settings
  post "/notifications/emails",                              to: "notifications#save_email_settings",        as: :save_notification_emails
  post "/notifications/own",                                 to: "notifications#toggle_own",                 as: :own_contributions
  post "/notifications/comment_email",                       to: "notifications#toggle_comment",             as: :notifications_comment_email
  post "/notifications/pull_request_review_email",           to: "notifications#toggle_pull_request_review", as: :notifications_pull_request_review_email
  post "/notifications/pull_request_push_email",             to: "notifications#toggle_pull_request_push",   as: :notifications_pull_request_push_email
  get  "/notifications/unsubscribe-vulnerability/:data",     to: "notifications#email_mute_vulnerabilities", as: :email_mute_vulnerabilities
  post "/notifications/vulnerability",                       to: "notifications#toggle_vulnerability",       as: :notifications_vulnerability
  post "/notifications/vulnerability_email",                 to: "notifications#toggle_vulnerability_email", as: :notifications_vulnerability_email
  post "/notifications/digest",                              to: "notifications#toggle_digest_subscription", as: :notifications_digest
  post "/notifications/continuous-integration",              to: "notifications#toggle_ci",                  as: :notifications_ci
  get  "/watching",                                          to: "notifications#watching",                   as: :watching
  get  "/repo_owners",                                       to: "notifications#repo_owners",                as: :notifications_repo_owners
  get  "/notifications/:repository_id/watch_subscription",   to: "notifications#watch_subscription",      as: :notification_watch_subscription
  get  "/notifications/indicator",                           to: "notifications_indicator#show",             as: :notifications_indicator
  post "/notifications/unsubscribe/dependabot-alerts/:email_type/:token", to: "dependabot/dependabot_alerts_one_click_unsubscriptions#create", constraints: { email_type: /(new-vulnerabilities|vulnerability-digest)/ }


  # NotificationSubscriptionsController
  get  "/notifications/subscriptions",                       to: "notification_subscriptions#index",             as: :notification_subscriptions
  get  "/notifications/subscriptions/repository_filter",     to: "notification_subscriptions#repository_filter", as: :notification_subscriptions_repository_filter
  post "/notification_subscriptions",                        to: "notification_subscriptions#create",            as: :create_notification_subscription
  post "/notifications/subscriptions/dismiss_notice",        to: "notification_subscriptions#dismiss_notice",    as: :dismiss_notification_subscriptions_notice
  delete "/notifications/subscriptions",                     to: "notification_subscriptions#destroy",           as: :destroy_notification_subscriptions

  # TeamsNotificationsController
  get  "/notifications/teams",                               to: "teams_notifications#index",                   as: :teams_notifications
  post "/notifications/teams",                               to: "teams_notifications#create",                  as: :create_team_notification_subscription
  get  "/notifications/watch_subscription",                  to: "teams_notifications#watch_subscription",      as: :team_notification_watch_subscription

  # Please, consider moving any notifications related route you add or change
  # to `config/routes/notifications.rb` instead.
  draw(:notifications)

  # Organization Repositories
  get    "/organizations/:organization_id/repository_imports/new", to: "repository_imports#new", as: :new_organization_repository_import

  org_repos_options = {
    controller: "repositories",
    path:       "/organizations/:organization_id/repositories",
    format:     false,
  }
  scope **org_repos_options do
    # Exploded out from map.resources :organizations
    get    "/", action: "index", as: :organization_repositories
    post   "/", action: "create"
    get    "/new", action: "new", as: :new_organization_repository
  end

  # OrganizationsController
  resources :organizations, only: [] do
    resource :settings, only: [] do
      draw :billing_vnext
    end
  end

  get    "/orgs/:org/dashboard",                            to: "organizations#show",              as: :org_dashboard
  get    "/orgs/:org/news-feed",                            to: "dashboard_feeds#show",            as: :organizations_news_feed
  post   "/organizations/transform",                        to: "orgs/transformations#create",     as: :transform_organizations
  get    "/organizations/transforming",                     to: "orgs/transformations#show",       as: :transforming_organizations
  post   "/organizations",                                  to: "organizations#create"
  get    "/organizations/new",                              to: "organizations#new"
  get    "/organizations/plan",                             to: "orgs/plan#show",                  as: :org_plan
  get    "/organizations/enterprise_plan",                  to: "orgs/enterprise_plan#show",       as: :org_enterprise_plan
  match  "/organizations/signup_billing",                   to: "orgs/signup_billing#show",        as: :org_signup_billing, via: [:get, :post]
  get    "/organizations/seats",                            to: "orgs/seats#show",                 as: :model_org_seats
  post   "/organizations/check_name",                       to: "orgs/name_checks#create",         as: :organization_check_name
  post   "/organizations/check_billing_email",              to: "orgs/billing_email_checks#create", as: :organization_check_billing_email
  get    "/organizations/:organization_id/invite",          to: "orgs/initial_invitees#show",      as: :invite_organization
  get    "/organizations/:organization_id/invite_form",     to: "orgs/initial_invitees_form#show", as: :organization_invite_form
  post   "/organizations/:organization_id/ignore_upgrade",  to: "orgs/upgrade_ignores#create",     as: :ignore_upgrade_organization
  put    "/organizations/:organization_id",                 to: "organizations#update",            as: :org_update
  patch  "/organizations/:organization_id/tos",             to: "orgs/terms_of_service#update",    as: :org_tos
  put    "/organizations/:organization_id/projects_enabled", to: "orgs/settings/projects#update", as: :organization_projects_enabled
  put    "/organizations/:organization_id/projects_classic_enabled", to: "orgs/settings/projects_classic#update", as: :organization_projects_classic_enabled
  put    "/organizations/:organization_id/default_repository_permission", to: "orgs/settings/default_repository_permission#update", as: :organization_default_repository_permission
  put    "/organizations/:organization_id/members_can_delete_repositories", to: "orgs/settings/member_repository_deletion#update", as: :organization_members_can_delete_repositories
  put    "/organizations/:organization_id/members_can_delete_issues", to: "orgs/settings/member_issue_deletion#update", as: :organization_members_can_delete_issues
  put    "/organizations/:organization_id/display_commenter_full_name", to: "orgs/settings/display_commenter_full_name#update", as: :organization_display_commenter_full_name
  put    "/organizations/:organization_id/readers_can_create_discussions", to: "orgs/settings/readers_can_create_discussions#update", as: :organization_readers_can_create_discussions
  put    "/organizations/:organization_id/members_can_update_protected_branches", to: "orgs/settings/members_can_update_protected_branches#update", as: :organization_members_can_update_protected_branches
  put    "/organizations/:organization_id/members_can_change_repo_visibility", to: "orgs/settings/members_can_change_repo_visibility#update", as: :organization_members_can_change_repo_visibility
  put    "/organizations/:organization_id/members_can_create_teams", to: "orgs/settings/team_creation#update", as: :organization_members_can_create_teams
  put    "/organizations/:organization_id/members_can_invite_outside_collaborators", to: "orgs/settings/members_can_invite_outside_collaborators#update", as: :organization_members_can_invite_outside_collaborators
  put    "/organizations/:organization_id/members_can_view_dependency_insights", to: "orgs/settings/dependency_insights#update", as: :organization_members_can_view_dependency_insights
  put    "/organizations/:organization_id/update_pages_creation_permission", to: "orgs/settings/pages_creation#update", as: :organization_update_pages_creation_permission
  put    "/organizations/:organization_id/private_repository_forking", to: "orgs/settings/private_repository_forking#update", as: :organization_private_repository_forking
  patch  "/organizations/:organization_id/repository_creation", to: "orgs/settings/repository_creation#update", as: :organization_repository_creation
  delete "/organizations/:organization_id",                 to: "organizations#destroy"
  post   "/organizations/:organization_id/leave",           to: "orgs/departures#create",          as: :leave_org
  put    "/organizations/:organization_id/rename",          to: "orgs/renames#update",             as: :org_rename
  get    "/account/organizations/new",                      to: "organizations#new",               as: :new_organization
  get    "/account/organizations/plan",                     to: "orgs/plan#show"
  get    "/account/organizations/new/:coupon",              to: "organizations#new"
  get    "/account/organizations/access_list_members",      to: "orgs/access_list_members#index"

  get "/organizations/:organization_id/enterprise_trial",
    to: "orgs/enterprise_trials#new",
    as: :new_org_enterprise_trial
  post "/organizations/:organization_id/enterprise_trial",
    to: "orgs/enterprise_trials#create",
    as: :create_org_enterprise_trial

  get    "/organizations/:organization_id/:login.private",  to: "atom_feeds#org_show",    as: :private_org_feed

  # Organization Settings
  put   "/organizations/:organization_id/settings/member_privileges/integration_access_requests", to: "orgs/settings/member_privileges/integration_access_requests#update", as: :organization_outside_collaborators_can_request_third_party_access
  put   "/organizations/:organization_id/settings/member_privileges/projects/base_permissions", to: "orgs/settings/member_privileges/projects/base_permissions#update", as: :organization_update_projects_base_permissions

  # OrganizationsController legacy URL redirects
  get "/organizations/:organization_id/settings", to: redirect("/organizations/%{organization_id}/settings/profile"), as: :organization_settings
  get "/organizations/:organization_id/edit", to: redirect("/organizations/%{organization_id}/settings/profile")
  get "/organizations/:organization_id", to: redirect("/orgs/%{organization_id}/dashboard")
  get "/organizations/:organization_id/settings/billing/per_seat", to: redirect("/account/upgrade?org=%{organization_id}&target=organization")

  if GitHub.enterprise?
    get "/organizations/:organization_id/import", to: "orgs/imports#index", as: :import_organization
  end

  # Manual Payments for orgs and user
  get "/settings/billing/bill_pay", to: "billing_settings/payments#new", as: :bill_pay_new
  get "/organizations/:organization_id/settings/billing/bill_pay", to: "billing_settings/payments#new", as: :org_bill_pay_new
  get "/settings/billing/bill_pay/:payment_id", to: "billing_settings/payments#check", as: :bill_pay_check

  # Payment methods (org and user)
  get     "/settings/billing/payment_method", to: "payment_method#zuora_payment_show", as: :zuora_payment
  get     "/settings/billing/payment/signature", to: "payment_method#zuora_payment_page_signature", as: :zuora_payment_page_signature
  get     "/settings/billing/payment_modal", to: "payment_method#show_modal",    as: :payment_modal
  put     "/settings/billing/payment", to: "payment_method#update"
  delete  "/settings/billing/:page", to: "payment_method#destroy", page: /payment|payment_information/

  # User invoices
  get    "/settings/billing/invoices/:invoice_number", to: "invoices#show", as: :show_invoice

  get     "/organizations/:organization_id/settings/billing/payment_modal", to: "payment_method#show_modal",   as: :org_payment_modal
  put     "/organizations/:organization_id/settings/billing/payment", to: "payment_method#update"
  delete  "/organizations/:organization_id/settings/billing/:page", to: "payment_method#destroy", page: /payment|payment_information/

  get     "/organizations/:organization_id/settings/billing/seats",        to: "seats#show",         as: :org_seats
  put     "/organizations/:organization_id/settings/billing/seats",        to: "seats#update"
  get     "/organizations/:organization_id/settings/billing/remove_seats", to: "seats#remove_seats", as: :remove_org_seats
  put     "/organizations/:organization_id/settings/billing/switch",       to: "seats#switch",       as: :org_switch_to_seats
  put     "/organizations/:organization_id/settings/billing/trade_screening_update", to: "seats#trade_screening_update", as: :org_trade_screening_update
  delete  "/organizations/:organization_id/settings/billing/seats",        to: "seats#cancel",       as: :cancel_org_seats

  get     "/organizations/:organization_id/settings/billing/invoices/:invoice_number", to: "invoices#show", as: :show_invoice_org
  get     "/organizations/:organization_id/settings/billing/invoices/:invoice_number/pay", to: "invoices#pay", as: :pay_invoice
  get     "/organizations/:organization_id/settings/billing/invoices/:invoice_number/payment_method", to: "invoices#payment_method", as: :invoice_payment_method
  get     "/organizations/:organization_id/settings/billing/invoices/:invoice_number/signature", to: "invoices#payment_page_signature", as: :invoice_signature

  get    "/organizations/:organization_id/settings/ssh_certificate_authorities/new", to: "ssh_certificate_authorities#new",     as: :ssh_certificate_authorities_new_organization
  post   "/organizations/:organization_id/settings/ssh_certificate_authorities",     to: "ssh_certificate_authorities#create",  as: :ssh_certificate_authorities_organization
  delete "/organizations/:organization_id/settings/ssh_certificate_authorities/:id", to: "ssh_certificate_authorities#destroy", as: :ssh_certificate_authority_organization
  patch  "/organizations/:organization_id/settings/ssh_certificate_authorities/:id/require_expiration",     to: "ssh_certificate_authority_expiration#update",  as: :ssh_certificate_authorities_require_expiration_organization

  get    "/ghost_pilot/recent_interactions", to: "ghost_pilot/recent_interactions#index"
  get    "/ghost_pilot/:user_id/:repository/issues/:id", to: "ghost_pilot/issue_summaries#show", as: :ghost_pilot_issue_summary
  get    "/ghost_pilot/summary/:user_id/:repository/:range", to: "ghost_pilot/diff_summaries#show", as: :ghost_pilot_diff_summary, range: /.+/

  # Packages (org and user)
  if !GitHub.enterprise? || (GitHub.enterprise? && GitHub.registry_v2_enabled_for_enterprise?)
    # special route to support redirecting to the actual package view page from users clicking on the link from the Docker CLI
    # https://github.com/github/c2c-package-registry/issues/2022
    get "/-/:user_id/packages/:ecosystem/package/:name", to: "registry_two/packages#package_view_redirect", as: :packages_two_redirect_view, constraints: { user_id: USERID_REGEX, name: PACKAGE_DEPENDENCY_REGEX }
    scope "/:user_type/:user_id", constraints: { user_type: /users|orgs/, user_id: USERID_REGEX } do
      get    "/packages", to: "registry_two/packages#index", as: :packages_two
      get    "/packages/:ecosystem", to: "registry_two/packages#ecosystem_index"

      constraints name: /.+/ do
        scope "/packages/:ecosystem/:name/settings" do
          get    "/", to: "registry_two/package_settings#show", as: :package_settings
          get    "/actions_access", to: "registry_two/package_settings#actions_access", as: :package_actions_access
          get    "/collaborator_suggestions", to: "registry_two/package_settings#collaborator_suggestions", as: :package_collaborator_suggestions
          get    "/repository_suggestions", to: "registry_two/package_settings#repository_suggestions", as: :package_repository_suggestions
          get    "/repository_list", to: "registry_two/package_settings#repository_list", as: :package_repository_list
          get    "/toolbar_actions", to: "registry_two/package_settings#toolbar_actions",  as: :package_members_toolbar_actions
          get    "/repositories_toolbar_actions", to: "registry_two/package_settings#repositories_toolbar_actions", as: :package_repositories_toolbar_actions

          post   "/activate_action_package", to: "registry_two/package_settings#activate_action_package", as: :activate_action_package
          post   "/add_collaborator", to: "registry_two/package_settings#add_collaborator", as: :add_package_collaborator
          post   "/add_actions_access", to: "registry_two/package_settings#add_actions_access", as: :add_package_actions_access
          post   "/bulk_add_actions_access", to: "registry_two/package_settings#bulk_add_actions_access", as: :bulk_add_package_actions_access
          post   "/bulk_add_codespaces_access", to: "registry_two/package_settings#bulk_add_codespaces_access", as: :bulk_add_package_codespaces_access
          post   "/add_codespaces_access", to: "registry_two/package_settings#add_codespaces_access", as: :add_package_codespaces_access
          post   "/update_collaborator", to: "registry_two/package_settings#update_collaborator", as: :update_package_collaborator
          post   "/update_actions_access", to: "registry_two/package_settings#update_actions_access", as: :update_package_actions_access
          post   "/bulk_update_collaborators", to: "registry_two/package_settings#bulk_update_collaborators", as: :bulk_update_package_collaborators
          post   "/bulk_update_actions_access", to: "registry_two/package_settings#bulk_update_actions_access", as: :bulk_update_package_actions_access
          post   "/change_visibility", to: "registry_two/package_settings#change_visibility", as: :change_package_visibility
          put   "/change_active_sync_perms", to: "registry_two/package_settings#change_active_sync_perms", as: :change_package_active_sync_perms
          put   "/change_actions_package_sharing_policy", to: "registry_two/package_settings#change_actions_package_sharing_policy", as: :change_actions_package_sharing_policy
          post  "/toggle_list_action_package", to: "registry_two/package_settings#toggle_list_action_package", as: :toggle_list_action_package
          put   "/update_action_category_contact_email", to: "registry_two/package_settings#update_action_category_contact_email", as: :update_action_category_contact_email
          post   "/verify_email_format", to: "registry_two/package_settings#verify_email_format", as: :verify_email_format

          delete "/remove_collaborator", to: "registry_two/package_settings#remove_collaborator", as: :remove_package_collaborator
          delete "/remove_actions_access", to: "registry_two/package_settings#remove_actions_access", as: :remove_package_actions_access
          delete "/remove_codespaces_access", to: "registry_two/package_settings#remove_codespaces_access", as: :remove_package_codespaces_access
          delete "/delete_package", to: "registry_two/package_settings#delete_package", as: :delete_package
        end

        put    "/packages/:ecosystem/:name/versions/:version/restore", to: "registry_two/package_versions#restore", as: :package_versions_two_restore, constraints: { version: /.+/ }
        put "/packages/:ecosystem/:name/restore", to: "registry_two/packages#restore", as: :packages_two_restore
        # TODO: This should become #show once it's ready to ship.
        # https://gist.github.com/noahmatisoff/914d694d7f071831c6af77af444b74f8
        get    "/packages/:ecosystem/package/:name/repo_dialog", to: "registry_two/packages#repo_dialog", as: :packages_two_repo_dialog
        put    "/packages/:ecosystem/package/:name/update_repo", to: "registry_two/packages#update_repo", as: :packages_two_update_repo
        put    "/packages/:ecosystem/package/:name/remove_repo", to: "registry_two/packages#remove_repo", as: :packages_two_remove_repo
        get    "/packages/:ecosystem/package/:name/repository_items", to: "registry_two/repository_items#index", as: :packages_two_repository_items
        get    "/packages/:ecosystem/package/:name/search_repositories", to: "registry_two/search_repositories#index", as: :packages_two_search_repositories
        get    "/packages/:ecosystem/package/:name", to: "registry_two/packages#package_view", as: :packages_two_view
        get    "/packages/:ecosystem/:name/versions", to: "registry_two/package_versions#show", as: :package_versions_two
        get    "/packages/:ecosystem/:name/versions/:version/reclaimed_storage", to: "registry_two/package_versions#reclaimed_storage_version", as: :reclaimed_storage_version_partial, constraints: { version: /.+/ }
        get    "/packages/:ecosystem/:name/:version/edit", to: "registry_two/packages#edit", as: :edit_package_description
        post   "/packages/:ecosystem/:name/:version/edit", to: "registry_two/packages#commit", as: :commit_package_description
        post   "/packages/:ecosystem/:name/:version/preview", to: "registry_two/packages#preview", as: :packages_preview
        get    "/packages/:ecosystem/:name/:version/readme", to: "registry_two/package_version_readme#show", as: :package_version_readme_two
        get    "/packages/:ecosystem/:name/:version", to: "registry_two/packages#show", as: :package_two
        delete "/packages/:ecosystem/:name/versions/:version/delete_package_version", to: "registry_two/package_versions#delete_package_version", as: :delete_package_version, constraints: { version: /.+/ }
        get    "/packages/:ecosystem/:name", to: "registry_two/packages#show"
      end
    end
  end

  # Planning
  get "/organizations/:organization_id/settings/issue-types",     to: "orgs/issue_types#index", as: :organization_issue_type_settings
  get "/organizations/:organization_id/settings/issue-types/new", to: "orgs/issue_types#new",  as: :organization_issue_types_new
  get "/organizations/:organization_id/settings/issue-types/:id", to: "orgs/issue_types#edit",  as: :organization_issue_types_edit

  resources :organization_ip_allowlist_entries,
    path: "/organizations/:organization_id/settings/ip_allowlist_entries",
    only: %w(new create edit update destroy),
    controller: "ip_allowlist_entries"

  ##
  # Teams
  teams_options = {
    controller: "teams",
    path:       "/organizations/:organization_id/teams",
    format:     false,
  }

  # the collection of teams
  scope **teams_options do
    get  "/",    action: "index"
    get  "/new", action: "new"

    # a specific team
    scope path: "/:team_id", team_id: /\d+|[\w\.\-]+/i do
      get    "/", action: "show"
    end
  end

  scope path: "/organizations/:org", format: false do
    get   "/dashboard/pulls",       to: "issues#redirect_to_scoped_org_dashboard", pulls_only: true, as: nil
    get   "/dashboard/issues",      to: "issues#redirect_to_scoped_org_dashboard", as: nil
  end

  scope  module: :context_switcher do
    resources :contexts, only: [:index], as: :contexts
  end

  ##
  # Global navigation - Side Panels
  get "/_side-panels/:panel", to: "side_panels#show", as: :side_panels
  get "/_side-panel-items/:panel/:type", to: "side_panels/items#index", as: :side_panel_items
  post "/_context-region/:variant", to: "context_region#show", as: :context_region_variant

  ##
  # Dashboard
  get           "/dashboard/pulls",         to: "issues#redirect_to_scoped_org_dashboard", pulls_only: true
  get           "/dashboard/issues",        to: "issues#redirect_to_scoped_org_dashboard"

  # DashboardController
  get    "/dashboard",                  to: "dashboard#index",            as: :dashboard
  get    "/",                           to: "dashboard#index",            as: :home
  get    "/dashboard/my_top_repositories", to: "dashboard#top_repositories", as: :dashboard_my_top_repositories
  get    "/dashboard/top_repositories", to: "dashboard#top_repositories"
  get    "/dashboard/trending_repositories", to: "dashboard#trending_repositories"
  get    "/dashboard/ajax_context_list", to: "dashboard#ajax_context_list", as: :dashboard_ajax_context_list
  get    "/dashboard/discover",         to: redirect("/explore"), as: :dashboard_discover
  get    "/dashboard/recent-activity",  to: "dashboard#recent_activity", as: :dashboard_recent_activity
  get    "/dashboard/index/:page",      to: "dashboard#index"
  post   "/dashboard/dismiss_bootcamp", to: "dashboard#dismiss_bootcamp", as: :dismiss_bootcamp
  delete "/dashboard/dismiss_bootcamp", to: "dashboard#dismiss_bootcamp"
  get    "/dashboard/ajax_your_teams",  to: "dashboard#ajax_your_teams"
  get    "/dashboard/ajax_my_repositories", to: "dashboard#ajax_repositories"
  post   "/ignore_upgrade",             to: "dashboard#ignore_upgrade",    as: :ignore_upgrade
  get    "/dashboard/logged_out",       to: "dashboard#logged_out"
  get    "/dashboard/changelog",       to: "dashboard#changelog", as: :dashboard_changelog

  get    "/dashboard-feed", to: "dashboard_feeds#show", as: :dashboard_news_feed

  namespace :conduit do
    resource :for_you_feed, only: [:show], controller: :for_you_feed
    resource :filter, only: [:show, :update], controller: :filter
    resource :register_disinterest, only: [:create, :destroy], controller: :register_disinterest
    resource :topic_feeds, only: [:show], controller: :topic_feeds
    resource :org_feeds, only: [:show], controller: :org_feeds
  end

  namespace :dashboard do
    resources :favorites, only: [:index, :create]
    resource  :favorites_modal, controller: :favorites_modal, only: [:show]
    resource :favorites_pinnable_items, controller: :favorites_pinnable_items, only: [:show]

    resources :pinned_topics, controller: :pinned_topics, only: [:index]
  end

  get "/:login.private.actor", to: "atom_feeds#actor_show"
  get "/:login.private",       to: "atom_feeds#user_show", as: :private_feed

  get "/login/oauth/authorize",                        to: "oauth#request_access", as: :oauth_request, format: false
  post "/login/oauth/authorize",                       to: "oauth#authorize", as: :oauth_authorize, format: false
  match "/login/oauth/access_token",                   to: "oauth#access_token", as: :oauth_access_token, format: false, via: [:get, :post]
  get "/login/oauth/success",                          to: "oauth#success", as: :oauth_success, format: false
  post "/login/device/code",                           to: "oauth#request_device_authorization", as: :device_authorization_request, format: false
  post "/login/oauth/authorize_app",                   to: "oauth#account_picker", as: :oauth_account_picker, format: false
  get "/login/oauth/select_account",                   to: "switch_account#oauth_select_account",    as: :oauth_select_account, format: false

  # TODO add GHES/GHE.com support.
  unless GitHub.single_or_multi_tenant_enterprise?
    get "/.well-known/oauth-authorization-server/login/oauth", to: "oauth_authorization_server#oauth_authorization_server", as: :oauth_authorization_server, defaults: { format: "json" }
  end

  get "/login/oauth/.well-known/openid-configuration", to: "oauth_identity#openid_configuration", as: :oauth_openid_configuration, defaults: { format: "json" }
  get "/login/oauth/.well-known/jwks",                 to: "oauth_identity#jwks", as: :oauth_jwks, defaults: { format: "json" }

  get  "/login/device",                to: "device_authorization#user_code_prompt",                as: :user_code_prompt
  post "/login/device/confirmation",   to: "device_authorization#request_access",                  as: :device_request
  post "/login/device/authorize",      to: "device_authorization#authorize",                       as: :device_authorize
  get  "/login/device/success",        to: "device_authorization#success",                         as: :device_success
  get  "/login/device/failure",        to: "device_authorization#failure",                         as: :device_failure
  get  "/login/device/select_account", to: "switch_account#device_authorization_select_account",   as: :device_authorization_select_account
  post "/login/device/select_account", to: "switch_account#device_authorization_selected_account", as: :device_authorization_selected_account

  get "/stars", to: "stars#index", format: false
  get "/stars/:user", to: "stars#user_stars", as: :users_stars, format: false
  get "/stars/:user/repositories", to: "stars#user_repositories", as: :users_stars_repositories, format: false
  get "/stars/:user/topics", to: "stars#user_topics", as: :users_stars_topics, format: false

  # Lists
  resources :user_lists, path: "/stars/:user/lists", param: :slug, only: [:show, :create, :update, :destroy] do
    get "/activity", to: "conduit/user_list_feeds#show"
  end

  resource :user_list_checks, path: "/stars/:user/list-check", only: [:create]
  resource :user_list_menu_batches, path: "/stars/:user/list-menu-batch", only: [:create]

  ##
  # SessionsController
  get  "/session",                            to: redirect("/login")
  post "/session",                            to: "sessions#create"
  get  "/logout",                             to: "sessions#confirm_logout",                        as: :confirm_logout
  post "/logout",                             to: "sessions#destroy",                               as: :kill_session
  post "/sessions/remove_inactive",           to: "sessions#remove_inactive",                       as: :remove_inactive_session
  get  "/login",                              to: "sessions#new",                                   as: :login
  get  "/suspended",                          to: "sessions#suspended",                             as: :suspended
  get  "/sessions/two-factor",                to: "sessions#two_factor_prompt",                     as: :two_factor_prompt
  get  "/sessions/two-factor/app",            to: "sessions#two_factor_app_prompt",                 as: :two_factor_app_prompt
  get  "/sessions/two-factor/sms",            to: "sessions#two_factor_sms_prompt",                 as: :two_factor_sms_prompt
  get  "/sessions/two-factor/sms/confirm",    to: "sessions#two_factor_sms_confirm",                as: :two_factor_sms_confirm
  post "/sessions/two-factor/sms/confirm",    to: "sessions#two_factor_sms_send",                   as: :two_factor_sms_send
  post "/sessions/two-factor",                to: "sessions#two_factor_authenticate",               as: :two_factor
  get  "/sessions/two-factor/webauthn",       to: "sessions#webauthn_prompt",                       as: :webauthn_prompt
  post "/sessions/two-factor/webauthn",       to: "sessions#webauthn_authenticate",                 as: :webauthn_authenticate
  get  "/sessions/two-factor/mobile",         to: "sessions#github_mobile_two_factor_prompt",       as: :github_mobile_two_factor_prompt
  get  "/sessions/two-factor/mobile_metrics", to: "sessions#github_mobile_navigating_away_metrics", as: :github_mobile_navigating_away_metrics
  post "/sessions/two-factor/mobile_poll",    to: "sessions#github_mobile_two_factor_status",       as: :github_mobile_two_factor_status
  get  "/sessions/trusted-device",            to: "sessions#trusted_device_registration_prompt",    as: :trusted_device_registration_prompt
  get "/sessions/trusted-device/upgrade/:id", to: "sessions#trusted_device_upgrade_prompt",         as: :trusted_device_upgrade_prompt
  post "/sessions/trusted-device/continue",   to: "sessions#trusted_device_continue",               as: :trusted_device_continue
  post "/sessions/trusted-device/decline",    to: "sessions#trusted_device_decline",                as: :trusted_device_decline
  get  "/sessions/two-factor/recovery",       to: "sessions#two_factor_recover_prompt",             as: :two_factor_recover_prompt
  post "/sessions/two-factor/recovery",       to: "sessions#two_factor_recover",                    as: :two_factor_recover
  post "/sessions/two-factor/resend",         to: "sessions#resend_two_factor_sms",                 as: :two_factor_resend
  post "/sessions/two-factor/send-fallback",  to: "sessions#send_two_factor_fallback_sms",          as: :two_factor_send_fallback
  get  "/sessions/sudo_modal",                to: "sessions#sudo_modal",                            as: :sudo_modal
  post "/sessions/sudo",                      to: "sessions#sudo",                                  as: :sudo
  post "/sessions/sudo/mobile",               to: "sessions#github_mobile_sudo_prompt",             as: :sudo_prompt_mobile
  post "/sessions/sudo/mobile_poll",          to: "sessions#github_mobile_sudo_status",             as: :sudo_status_mobile
  post "/sessions/sudo/email",                to: "sessions#email_sudo_prompt",                     as: :sudo_prompt_email
  get  "/sessions/in_sudo",                   to: "sessions#in_sudo",                               as: :in_sudo
  get  "/sessions/kill_sudo",                 to: "sessions#kill_sudo",                             as: :kill_sudo

  # AccountSwitcher
  get  "/switch_account",                  to: "switch_account#index",                           as: :list_accounts
  post "/switch_account",                  to: "switch_account#update",                          as: :switch_account

  # TwoFactorRecoveryRequestController
  unless GitHub.enterprise?
    post  "/sessions/recovery/start",     to: "two_factor_recovery_request#start",             as: :two_factor_recovery_request_start
    get  "/sessions/recovery",            to: "two_factor_recovery_request#prompt",            as: :two_factor_recovery_request
    post  "/sessions/recovery/send",      to: "two_factor_recovery_request#send_otp",          as: :two_factor_recovery_request_send_otp
    post  "/sessions/recovery/otp",       to: "two_factor_recovery_request#verify_otp",        as: :two_factor_recovery_request_verify_otp
    post  "/sessions/recovery/device",    to: "two_factor_recovery_request#verify_device",     as: :two_factor_recovery_request_verify_device
    get  "/sessions/recovery/ssh",        to: "two_factor_recovery_request#enter_ssh_key",     as: :two_factor_recovery_request_enter_ssh_key
    post  "/sessions/recovery/ssh",       to: "two_factor_recovery_request#verify_ssh_key",    as: :two_factor_recovery_request_verify_ssh_key
    get  "/sessions/recovery/token",      to: "two_factor_recovery_request#enter_token",       as: :two_factor_recovery_request_enter_token
    post  "/sessions/recovery/token",     to: "two_factor_recovery_request#verify_token",      as: :two_factor_recovery_request_verify_token
    post  "/sessions/recovery/without_password",     to: "two_factor_recovery_request#without_password",  as: :two_factor_recovery_request_without_password

    get "/sessions/recovery/:id/abort/:token",   to: "two_factor_recovery_request#abort",         as: :two_factor_recovery_abort_request
    post "/sessions/recovery/:id/abort/:token",  to: "two_factor_recovery_request#confirm_abort", as: :two_factor_recovery_confirm_abort_request

    get  "/sessions/recovery/:id/continue/:token",  to: "two_factor_recovery_request#continue",          as: :two_factor_recovery_continue
    post  "/sessions/recovery/:id/continue/:token", to: "two_factor_recovery_request#confirm_continue",  as: :two_factor_recovery_completed

    get  "/sessions/recovery/metrics",    to: "two_factor_recovery_request#account_recovery_abort_metrics", as: :two_factor_recovery_account_recovery_abort_metrics

    post "/sessions/recovery/:id/unlink_email",    to: "two_factor_recovery_request#unlink_email",         as: :two_factor_recovery_unlink_email
  end

  # EmailUnlinkController
  unless GitHub.enterprise?
    get  "/sessions/email_unlink/:token",            to: "email_unlink#index",            as: :email_unlink_index
    put  "/sessions/email_unlink/:token",            to: "email_unlink#update",           as: :email_unlink_send_verification
    post  "/sessions/email_unlink/:token",           to: "email_unlink#submit",           as: :email_unlink_submit
  end

  if GitHub.sign_in_analysis_enabled? || Rails.env.test?
    get  "/sessions/verified-device",             to: "sessions#verified_device_prompt", as: :verified_device_prompt
    post "/sessions/verified-device",             to: "sessions#verified_device_authenticate", as: :verified_device_authenticate
    get  "/sessions/verified-device/mobile",      to: "sessions#github_mobile_verified_device_prompt", as: :github_mobile_verified_device_prompt
    post "/sessions/verified-device/mobile_poll", to: "sessions#github_mobile_verified_device_status", as: :github_mobile_verified_device_status
    post "/sessions/verified-device/resend",      to: "sessions#resend_verification_email", as: :resend_verification_email
  end

  # nginx auth_request endpoint for Enterprise2 private mode
  if GitHub.private_mode_enabled?
    get "/sessions/_auth_request_bounce", to: "sessions#auth_request_bounce", as: :auth_request_bounce
  end

  if GitHub.enterprise?
    # CAS, GitHub OAuth
    #
    # OmniAuth needs the prefix path `/auth/:provider` to 404 to initiate the auth request
    # for external auth providers (CAS)
    get  "/auth/:provider",          to: "sessions#external_provider"
    get  "/auth/:provider/callback", to: "sessions#create"  # CAS
    post "/auth/:provider/callback", to: "sessions#create"
    get  "/auth/failure",            to: redirect("/login")

    # Custom mandatory message
    resources :mandatory_message_views, only: [:create]
  end

  # SAML
  #
  #  /saml/consume  - callback endpoint for idP to POST authentication requests
  if GitHub.enterprise?
    post "/saml/consume",  to: "sessions#create"
  end
  get  "/saml/metadata", to: "saml#metadata"

  ##
  # UserSessionsController
  delete "/sessions/:id/revoke", to: "settings/user_sessions#revoke", as: :user_sessions_revoke

  ##
  # PasswordResetsController
  get  "/password_reset",                     to: "password_resets#new",         as: :password_reset
  post "/password_reset",                     to: "password_resets#create",      as: :create_password_reset
  get  "/password_reset/:token",              to: "password_resets#edit",        as: :edit_password_reset
  post "/password_reset/:token/2fa",          to: "password_resets#check_otp",   as: :check_password_reset_otp
  post "/password_reset/:token/2fa/fallback", to: "password_resets#fallback",    as: :password_reset_fallback
  put  "/password_reset/:token",              to: "password_resets#update",      as: :update_password_reset
  get  "/password_reset/:token/mobile",       to: "password_resets#mobile",      as: :edit_password_reset_mobile
  post "/password_reset/:token/mobile_poll",  to: "password_resets#mobile_status", as: :check_password_reset_mobile_status

  ##
  # Explore
  get "/explore",           to: "explore#index",            as: :explore
  get "/explore/subscribe", to: redirect("/explore/email"), as: :explore_subscribe
  get "/discover",          to: redirect("/explore"),       as: :discover_repositories

  if GitHub.enterprise?
    get "/topics", to: redirect("/explore"), as: :topics
    get "/topic", to: redirect("/explore")
    get "/topics/:topic_name", to: redirect("/explore"), as: :topic_show
    get "/topic/:topic_name", to: redirect("/explore")
  else
    get "/topics", to: "topics#index", as: :topics
    get "/topics/:topic_name", to: "topics#show", as: :topic_show

    get "/topic", to: redirect("/topics")
    get "/topic/:topic_name", to: redirect("/topics/%{topic_name}")
  end

  get "/showcases",         to: "showcases#index",   as: :showcases
  get "/showcases/search",  to: "showcases#search",  as: :showcases_search
  get "/showcases/:id",     to: "showcases#show",    as: :showcase_collection
  constraints format: "html" do
    get "/collections",       to: "collections#index", as: :collections
    get "/collections/:slug", to: "collections#show",  as: :collection
  end

  ##
  # Trending
  get "/trending/developers(/:language)", to: "trending#developers", as: :trending_developers, constraints: { language: /[^\/]+/ }
  get "/trending(/:language)",            to: "trending#index",      as: :trending_index, constraints: { language: /[^\/]+/ }

  ##
  # Enterprise Activity Dashboards (restricted to Enterprise at the controller level)
  get "/dashboards/audit-log", to: redirect(path: "/admin/audit-log")

  # Signup redesign experiment
  # https://github.com/github/communities-nux/issues/4
  if GitHub.enterprise? # https://github.com/github/communities-nux/issues/145
    get "/signup", to: redirect("/join"),           as: :nux_signup
  else
    resources :signup, only: [:new, :create], path_names: { new: "/" }, controller: "signups", as: :nux_signup
  end

  resources :signup, only: [:new, :create], path_names: { new: "/" }, controller: "signups", as: :nux_signup
  resources :password_validity_checks, only: [:create]
  resources :email_validity_checks, only: [:create]
  resources :account_verifications, only: [:index, :create] do
    collection do
      get "confirm/:verification/:token", as: :accountless_confirm, to: "accountless_confirmations#show"

      resource :resend, only: [:create], controller: "account_verifications/resend", as: :resend_account_verification
    end
  end

  # signup controller
  get   "/join",                  to: "signup#join",           as: :signup
  post  "/join",                  to: "signup#create_account"
  get   "/join/plan",             to: "signup#plan",           as: :signup_plan
  post  "/join/plan",             to: "signup#process_plan_selection"
  get   "/join/trial",            to: "signup#enterprise_trial_redirect", as: :enterprise_trial_redirect
  post  "/join/select_plan",      to: "signup#select_plan",    as: :select_plan
  get   "/signup_check/username", to: "signup#username_check", as: :username_check_get
  post  "/signup_check/email",    to: "signup#email_check",    as: :email_check
  get   "/join/get-started",      to: "signup#get_started",    as: :get_started
  get   "/join/welcome",          to: redirect("/")
  post  "/join/recommended_plan", to: redirect("/410")

  # redesigned billing settings
  if GitHub.billing_enabled?
    get "/join/billing",          to: "signup#billing",        as: :signup_billing
    get "/join/signature",        to: "signup#zuora_payment_page_signature",        as: :signup_signature
  end

  # user identification survey
  get   "/join/customize",              to: "user_identification_survey_response#new",          as: :signup_customize
  post  "/join/customize",              to: "user_identification_survey_response#create",       as: :user_identification_survey_response
  get   "/join/customize/autocomplete", to: "user_identification_survey_response#autocomplete", as: :user_identification_survey_response_autocomplete

  # Getting started interstitial
  get "/getting-started", to: redirect(GitHub.help_url)

  # Old signup urls
  get "/signup",             to: redirect("/join")
  get "/signup/:plan",       to: redirect("/join")
  get "/signup/:plan/:code", to: redirect("/join")

  get "/timeline(.:format)", to: "events#index", as: :timeline_feed, format: %w[atom json]

  get "/security-advisories(.:format)", to: "security_advisories#index", as: :security_advisory_feed, format: ["atom"]

  constraints(id: AdvisoryDB.valid_ghsa_id_input_pattern) do
    get "/advisories",     to: "global_advisories#index", as: :global_advisories
    get "/advisories/cwe-filter", to: "global_advisories#cwe_filter", as: :global_advisories_cwe_filter
    get "/advisories/:id", to: "global_advisories#show", as: :global_advisory
    get "/advisories/:id/history", to: "global_advisories#history", as: :global_advisory_history
    get "/advisories/:id/dependabot", to: "global_advisories#dependabot_alerts", as: :global_advisory_dependabot_alerts
    get "/advisories/:id/dependabot-count", to: "global_advisories#dependabot_alerts_count", as: :global_advisory_dependabot_alerts_count
    get "/advisories/:id/organization-filter", to: "global_advisories#organization_filter", as: :global_advisories_organization_filter
    get "/advisories/:id/hovercard", to: "hovercards/advisories#show", as: :advisory_hovercard
    get "/advisories/:id/improve", to: "global_advisory_improvements#new", as: :new_global_advisory_improvement
    post "/advisories/:id/improve", to: "global_advisory_improvements#create", as: :create_global_advisory_improvement
    post "/advisories/calculate_cvss_score", to: "advisories#calculate_cvss_score", as: :calculate_cvss_score
    get "/advisories/cwe-autocomplete", to: "advisories#cwe_autocomplete", as: :cwe_autocomplete
    get "/advisories/package-url", to: "advisories#get_package_url", as: :get_package_url
  end

  get "/advisories/cwes/:id/hovercard", to: "hovercards/cwe#show"
  get "/advisories/cwes/:id", to: "repos/security_and_analysis/cwe#show", as: :cwe_details

  post  "/preview", to: "comment_preview#show", as: :preview, format: false
  post "/site/preview", to: "comment_preview#show"

  get "/account",          controller: "users", action: "edit", as: "account", format: false, tab: "profile"
  get "/account/:tab",     controller: "users", action: "edit", as: "account_tab", format: false, tab: /admin|email|ssh|job|connections/
  put "/account",          controller: "users", action: "update", format: false
  put "/account/password", controller: "users", action: "change_password", as: "change_password", format: false
  post "/account/rename_check", controller: "users", action: "rename_check", as: "rename_check"

  get  "/account/billing",            to: "users#billing",          as: :billing
  get  "/account/billing/:coupon",    to: "users#billing"
  get  "/account/notifications",      to: redirect("/settings/notifications")
  get  "/account/repositories",       to: redirect("/")
  post "/account/leave_repo/:repo",   to: "account#leave_repo",     as: :leave_repo
  put  "/account/read_broadcast/:id", to: "account#read_broadcast", as: :read_broadcast

  # TODO: check whether or not this can be removed. We have an `account/upgrade` route
  # above which is fenced by billing_enbled? this means that this route would likely only
  # be available in enterprise mode. Will need to check there whether if it's something useful or not
  # Goes all the way back to https://github.com/github/github/pull/59741/files and prior
  get "/account/upgrade",       to: "users#billing",       as: :plan_upgrade,       format: false


  # User settings

  # redirects
  get "/account/organizations", to: redirect("/settings/organizations")
  get "/.well-known/change-password", to: redirect("/settings/security")
  get "/account/admin", to: redirect("/settings/admin")

  get    "/users/settings/security_products",                           to: "users/settings/security_products#index",   as: :settings_users_security_products
  get    "/users/settings/security_products/configurations/new",        to: "users/settings/security_products#new",     as: :settings_users_security_configurations_new
  post   "/users/settings/security_products/configurations",            to: "users/settings/security_products#create",  as: :settings_users_security_configurations_create
  get    "/users/settings/security_products/configurations/edit/:id",   to: "users/settings/security_products#edit",    as: :settings_users_security_configurations_edit
  put    "/users/settings/security_products/configurations/:id",        to: "users/settings/security_products#update",  as: :settings_users_security_configurations_update
  delete "/users/settings/security_products/configurations/:id",        to: "users/settings/security_products#destroy", as: :settings_users_security_configurations_destroy
  get    "/users/settings/security_products/configurations/view/:id",   to: "users/settings/security_products#show",    as: :settings_users_security_configurations_view

  get    "/users/settings/security_products/configuration/:id/repositories_count",      to: "users/settings/security_products#repositories_count",          as: :settings_users_security_configurations_repositories_count
  put    "/users/settings/security_products/configuration/:id/apply_configuration",     to: "users/settings/security_products#apply_configuration",         as: :settings_users_security_configurations_apply_configuration
  delete "/users/settings/security_products/configuration/detach_configuration",        to: "users/settings/security_products#detach_configuration",        as: :settings_users_security_configurations_detach_configuration
  post   "/users/settings/security_products/configuration/apply_confirmation_summary",  to: "users/settings/security_products#apply_confirmation_summary",  as: :settings_users_security_configurations_apply_confirmation_summary

  # resources
  scope module: :settings do
    # This is a work in progress! We're slowly breaking SettingsController up
    # into multiple controllers that are owned by an appropriate team. If you're
    # doing that, please add your new routes here!
    # See https://github.com/github/communities/issues/787.
    resource :settings, only: [] do
      resource :profile, only: [:show], as: :user_profile
      get "/", controller: "profiles", action: :show

      resource :account_preferences, only: :show, path: "admin"
      resource :accessibility_preferences, only: [:show], path: "accessibility" do
        member do
          put :keyboard
          put :hovercards_enabled
          put :link_underlines
          put :motion
          put :paste_url_markdown
          put :announcement_preference_hovercard
        end
      end
      resource :security_analysis, only: [:show, :update]
      resource :security_checkup, only: :update
      resource :account_two_factor_requirements, only: [], path: "account_two_factor_requirement" do
        member do
          patch :dismiss_banner
          post :interrupt
        end
      end
      resource :email_preferences, only: [:show], path: "emails" do
        member do
          put :show_with_email_verification_banner
        end
      end
      resource :email_subscriptions, path: "emails/subscriptions" do
        collection do
          get "/", to: "email_subscriptions#index"
          get "/topics_by_email", to: "email_subscriptions#fetch_topics_by_email"
          get "/topics_by_params", to: "email_subscriptions#fetch_topics_by_cpm_params"
          get "/opt-in", to: "email_subscriptions#double_opt_in"
          get "/unsubscribe", to: "email_subscriptions#unsubscribe"
          patch "/update", to: "email_subscriptions#update", as: :update
          resource :link_request, only: [:new, :create], path: "link-request"
        end
      end
      resource :gravatar_status, only: :show
      resource :interaction, only: :update
      resource :primary_avatar, only: :destroy
      resource :profile_email, only: [:destroy]
      resource :rename_status, only: :show
      resource :security, only: :show
      resources :sessions, only: [:index] do
        member do
          delete :mobile_revoke
        end
      end

      resources :pages, only: :index
      resources :repositories, only: :index
      resources :deleted_repositories, only: :index
      resource :packages do
        get "/", action: :index
        put "/", action: :update
      end
      resources :organizations, only: :index
      resources :enterprises, only: :index

      resources :blocked_users, only: [:index, :create, :destroy, :update] do
        collection do
          resources :suggestions,
            module: :blocked_users,
            only: :index,
            as: :blocked_users_suggestions
        end
      end

      resource :appearance_preferences, only: [:show], path: "appearance" do
        scope module: :appearance_preferences do
          resource :color_mode, only: [:update]
          resource :fixed_width_font, only: [:update]
          resource :skin_tone, only: [:update]
          resource :tab_size, only: [:update]
        end
      end

      constraints id: /\d+/ do
        resources :keys, only: [:index, :show]
        resources :keys, only: [:index, :show], path: "ssh" do
          resources :organization_credential_authorizations,
            only: [:index], controller: "keys/ssh_keys/organization/credential_authorizations"
        end
      end

      resource :keys, only: [], path: "/" do
        scope module: :keys do
          resource :gpg_key, only: :new, path: "gpg"

          resource :ssh_key, only: [:new, :create], path: "ssh" do
            resources :audit, module: :audits, only: [], constraints: { id: /\d+/ } do
              resource :policy, only: :show
            end
          end
        end
      end

      resource :keys, module: :keys, only: [] do
        resource :commit_verification_status, only: :update
      end

      resource :notification_preferences, only: [:show], path: "notifications" do
        get "custom_routing", to: "notification_preferences#custom_routing"
        put "", to: "/notifications#update_settings", as: :update_notification_settings
      end

      resource :notification_preferences, only: [] do
        scope module: :notification_preferences do
          resources :organizations, only: [:update, :destroy]
        end
      end

      resource :two_factor_checkup, only: [:show, :update] do
        put "delay", to: "two_factor_checkups#edit", as: :delay
      end

      resource :nodeinfo_software, only: [:show]
      resources :models, only: :index, controller: "github_models"
    end

    resources :account_choices, only: :index, path: "account/choose"
  end

  resource :settings, only: [] do
    draw :billing_vnext
  end

  # Settings controller (legacy routes)
  # Try not to add new routes here - please see the new `User settings`
  # section above!
  get    "/settings/security-log",                                                              to: "settings/audit_log#index",                               as: :settings_user_audit_log
  get    "/settings/security-log/results",                                                      to: "settings/audit_log#results",                             as: :settings_user_audit_log_results
  get    "/settings/security-log/suggestions",                                                  to: "settings/audit_log#suggestions",                         as: :settings_user_audit_log_suggestions
  get    "/settings/security-log/export",                                                       to: "settings/audit_log_export#show",                         as: :settings_user_audit_log_export
  get    "/settings/security-log/export_status",                                                to: "settings/audit_log_export#export_status",                as: :settings_user_audit_log_export_status
  post   "/settings/security-log/export(.:format)",                                             to: "settings/audit_log_export#create",                       as: :settings_user_audit_log_export_create

  get    "/settings/two_factor_authentication/configure",                                       to: redirect("/settings/security", status: 301), as: :settings_user_two_factor_authentication_configuration
  get    "/settings/two_factor_authentication/intro",                                           to: redirect("/settings/two_factor_authentication/setup/intro", status: 301),  as: :settings_user_two_factor_authentication_intro
  get    "/settings/two_factor_authentication/setup/intro",                                     to: "two_factor#intro",                                       as: :settings_user_2fa_intro
  post   "/settings/two_factor_authentication/setup/initiate",                                  to: "two_factor#initiate",                                    as: :settings_user_2fa_initiate
  post   "/settings/two_factor_authentication/setup/send_sms",                                  to: "two_factor#send_two_factor_sms",                         as: :settings_user_2fa_sms
  post   "/settings/two_factor_authentication/setup/verify",                                    to: "two_factor#verify",                                      as: :settings_user_2fa_verify
  post   "/settings/two_factor_authentication/setup/recovery_download",                         to: "two_factor#recovery_download",                           as: :settings_user_2fa_recovery_download
  post   "/settings/two_factor_authentication/setup/enable",                                    to: "two_factor#enable",                                      as: :settings_user_2fa_enable
  post   "/settings/two_factor_authentication/setup/disable",                                   to: "two_factor#two_factor_authentication_disable",           as: :settings_user_2fa_disable
  post   "/settings/two_factor_authentication/setup/backup_number",                             to: "two_factor#add_two_factor_sms_backup",                   as: :settings_user_2fa_add_backup
  delete "/settings/two_factor_authentication/setup/backup_number",                             to: "two_factor#destroy_two_factor_sms_backup",               as: :settings_user_2fa_destroy_backup
  post   "/settings/two_factor_authentication/configure_factor",                               to: "two_factor#two_factor_authentication_configure_factor",         as: :settings_user_two_factor_authentication_configure_factor
  post   "/settings/two_factor_authentication/configure_factor_enable",                        to: "two_factor#two_factor_authentication_configure_factor_enable",         as: :settings_user_two_factor_authentication_configure_factor_enable
  delete "/settings/two_factor_authentication/disable_factor",                                  to: "two_factor#two_factor_authentication_disable_factor",    as: :settings_user_two_factor_authentication_disable_factor
  get  "/settings/two_factor_authentication/holiday_warning_banner",                          to: "two_factor#holiday_warning_banner",              as: :settings_user_2fa_holiday_warning_banner
  patch  "/settings/two_factor_authentication/holiday_warning_banner",                          to: "two_factor#dismiss_holiday_warning_banner",              as: :settings_user_2fa_dismiss_holiday_warning_banner
  post   "/settings/two_factor_authentication/login_preference",                                to: "two_factor#set_login_2fa_preference",                    as: :settings_user_2fa_login_preference

  get    "/settings/repositories",                                                              to: "settings#user_repositories",                             as: :settings_user_repositories
  get    "/settings/restore_repo/:id",                                                          to: "repos/restore#restore_status",                           as: :settings_restore_repo_status
  post   "/settings/restore_repo/:id",                                                          to: "repos/restore#restore",                                  as: :settings_restore_repo
  get    "/settings/restore_repo/:id/partial",                                                  to: "repos/restore#restore_partial",                          as: :settings_restore_repo_partial
  put    "/settings/default_branch",                                                            to: "settings/default_branch_names#update",                   as: :settings_user_default_branch
  post   "/settings/default_branch/check_name",                                                 to: "settings/default_branch_names#check_name",               as: :settings_user_default_branch_check_name
  get    "/settings/sessions/:id",                                                              to: "settings/user_sessions#show",                                     as: :settings_show_session
  get    "/settings/sessions/incomplete/:authentication_record_id",                             to: "settings/user_sessions#show",                                     as: :settings_show_incomplete_auth_record
  get    "/settings/sessions/authentications/:authentication_record_id",                        to: "settings/user_sessions#show",                                     as: :settings_show_auth_record
  get    "/settings/code_review_limits",                                                        to: "users/code_review_limits#show",                          as: :settings_user_code_review_limits
  put    "/settings/code_review_limits",                                                        to: "users/code_review_limits#update",                        as: :set_user_code_review_limits
  get    "/organizations/:organization_id/settings/profile",                                    to: "orgs/settings#index",                                    as: :settings_org_profile
  get    "/settings/contexts",                                                                  to: "settings/contexts#show",                                 as: :settings_available_contexts

  get    "/organizations/:organization_id/settings/packages",                                   to: "orgs/packages_settings#index",                            as: :settings_org_packages
  put    "/organizations/:organization_id/settings/packages",                                   to: "orgs/packages_settings#update",                           as: :settings_org_packages_update

  get    "/organizations/:organization_id/settings/codespaces",                                 to: "orgs/codespaces_settings#index",                         as: :settings_org_codespaces
  put    "/organizations/:organization_id/settings/codespaces/update_codespaces_user_limit",    to: "orgs/codespaces_settings#update_codespaces_user_limit",  as: :settings_org_codespaces_update_codespaces_user_limit
  put    "/organizations/:organization_id/settings/codespaces/update_codespaces_spending_limit",    to: "orgs/codespaces_settings#update_codespaces_spending_limit",  as: :settings_org_codespaces_update_codespaces_spending_limit
  put    "/organizations/:organization_id/settings/codespaces/update_trusted_repositories_access",     to: "orgs/codespaces_settings#update_trusted_repositories_access",   as: :settings_org_codespaces_update_trusted_repositories_access
  put    "/organizations/:organization_id/settings/codespaces/update_codespaces_ownership_settings", to: "orgs/codespaces_settings#update_ownership_setting", as: :settings_org_codespaces_update_ownership_setting
  post   "/organizations/:organization_id/settings/codespaces/user",           to: "orgs/codespaces_settings#grant_access",      as: :settings_org_codespaces_grant_access
  delete "/organizations/:organization_id/settings/codespaces/user",           to: "orgs/codespaces_settings#revoke_access",     as: :settings_org_codespaces_revoke_access
  get    "/organizations/:organization_id/settings/codespaces/suggestions",    to: "orgs/codespaces_settings#suggestions",       as: :settings_org_codespaces_suggestions
  get    "/organizations/:organization_id/settings/codespaces/policies",       to: "orgs/codespaces_settings/policies#index",    as: :settings_org_codespaces_policies
  post   "/organizations/:organization_id/settings/codespaces/policies",       to: "orgs/codespaces_settings/policies#create",   as: :settings_org_codespaces_create_policy
  get    "/organizations/:organization_id/settings/codespaces/policies/new",   to: "orgs/codespaces_settings/policies#new",      as: :settings_org_codespaces_policies_new
  get    "/organizations/:organization_id/settings/codespaces/policies/add_constraint_dropdown", to: "orgs/codespaces_settings/policies#add_constraint_dropdown", as: :settings_org_codespaces_policies_add_constraint_dropdown
  get    "/organizations/:organization_id/settings/codespaces/policies/repo_dialog_list", to: "orgs/codespaces_settings/policies#repo_dialog_list", as: :settings_org_codespaces_policies_repo_dialog_list
  put    "/organizations/:organization_id/settings/codespaces/policies/:identifier",       to: "orgs/codespaces_settings/policies#update",   as: :settings_org_codespaces_update_policy
  get    "/organizations/:organization_id/settings/codespaces/policies/:identifier/edit",  to: "orgs/codespaces_settings/policies#edit",     as: :settings_org_codespaces_policies_edit
  get    "/organizations/:organization_id/settings/codespaces/policies/additional_repo_dialog_list", to: "orgs/codespaces_settings/policies#additional_repo_dialog_list", as: :settings_org_codespaces_policies_additional_repo_dialog_list
  delete "/organizations/:organization_id/settings/codespaces/policies/:identifier",  to: "orgs/codespaces_settings/policies#destroy",     as: :settings_org_codespaces_delete_policy

  get    "/organizations/:organization_id/settings/code_review_limits",                         to: "orgs/code_review_limits#show",                           as: :settings_org_code_review_limits
  put    "/organizations/:organization_id/settings/code_review_limits",                         to: "orgs/code_review_limits#update",                         as: :set_org_code_review_limits
  get    "/organizations/:organization_id/settings/owners",                                     to: "orgs/settings/owners#index",                             as: :settings_org_owners
  get    "/organizations/:organization_id/settings/billing/summary",                            to: "orgs/settings/billing#index",                            as: :settings_org_billing
  get    "/organizations/:organization_id/settings/billing/lfs_bandwidth",                      to: "billing_settings#lfs_bandwidth_breakdown",               as: :settings_orgs_lfs_bandwidth_breakdown, target: "organization"
  get    "/organizations/:organization_id/settings/billing/lfs_storage",                        to: "billing_settings#lfs_storage_breakdown",                 as: :settings_orgs_lfs_storage_breakdown, target: "organization"
  get    "/organizations/:organization_id/billing/plans",                                       to: "billing_settings#plans",                                 as: :settings_org_plans
  get    "/organizations/:organization_id/settings/billing/actions_usage",                      to: "orgs/billing_settings/shared_products_usage#show_actions", as: :billing_settings_org_actions_usage
  get    "/organizations/:organization_id/settings/billing/packages_usage",                     to: "orgs/billing_settings/shared_products_usage#show_packages", as: :billing_settings_org_packages_usage
  get    "/organizations/:organization_id/settings/billing/shared_storage_usage",               to: "orgs/billing_settings/shared_products_usage#show_shared_storage", as: :billing_settings_org_storage_usage
  get    "/organizations/:organization_id/settings/billing/packages_storage_usage",             to: "orgs/billing_settings/shared_products_usage#show_packages_storage", as: :billing_settings_org_packages_storage_usage
  get    "/organizations/:organization_id/settings/billing/metered_usage",                      to: "orgs/billing_settings/metered_usage#show",               as: :billing_settings_org_metered_usage
  get    "/organizations/:organization_id/settings/billing/codespaces_usage",                   to: "orgs/billing_settings/codespaces_usage#show",            as: :billing_settings_org_codespaces_usage
  get    "/organizations/:organization_id/settings/billing/copilot_usage",                      to: "orgs/billing_settings/copilot_usage#show",               as: :billing_settings_org_copilot_usage
  get    "/organizations/:organization_id/settings/billing/usage_notification",                 to: "orgs/billing_settings/usage_notifications#show",         as: :billing_settings_org_usage_notification
  get    "/organizations/:organization_id/settings/billing/:tab",                               to: "orgs/settings/billing#index",                            as: :settings_org_billing_tab, tab: /payment_information|spending_limit|subscriptions|past_invoices/
  get    "/organizations/:organization_id/settings/billing/cost_management",                    to: redirect("/organizations/%{organization_id}/settings/billing/spending_limit")
  post   "/organizations/:organization_id/settings/spending_limit",                             to: "orgs/settings/spending_limit#create",                    as: :settings_org_spending_limit
  post   "/organizations/:organization_id/settings/usage_notification_settings",                to: "orgs/settings/usage_notification_settings#create",       as: :settings_org_usage_notification_settings
  get    "/organizations/:organization_id/settings/billing/plan_downgrade/:plan",               to: "orgs/billing_settings/plan_downgrade#show",              as: :settings_org_plan_downgrade

  # For individual settings
  scope "/settings/billing", module: "customers/billing" do
    resources :usage_report, only: [:create, :show]

    post "/copilot_premium_usage_report", to: "copilot_premium_usage_report#create"
  end

  # For organization settings
  scope "/organizations/:organization_id/settings/billing", module: :orgs do
    resources :usage_report, only: [:create, :show]

    post "/copilot_premium_usage_report", to: "copilot_premium_usage_report#create"
  end

  post   "/organizations/:organization_id/settings/billing/profile_linking",                    to: "orgs/billing_settings/billing_information_linking#update", as: :billing_information_linking

  get    "/organizations/:organization_id/settings/pages",                                      to: "orgs/settings/pages#index",                              as: :settings_org_pages

  get "/organizations/:organization_id/settings/enterprise_upgrades/new",
    to: "orgs/enterprise_upgrades#new",
    as: :new_org_enterprise_upgrade
  post "/organizations/:organization_id/settings/enterprise_upgrades",
    to: "orgs/enterprise_upgrades#create",
    as: :create_org_enterprise_upgrade

  post "/organizations/:organization_id/settings/check_enterprise_slug",
    to: "orgs/settings#check_slug",
    as: :settings_org_check_enterprise_slug

  get "/organizations/:organization_id/settings/enterprise_purchase_upgrades/new",
    to: "orgs/enterprise_purchase_upgrades#new",
    as: :new_org_enterprise_purchase_upgrade
  post "/organizations/:organization_id/settings/enterprise_purchase_upgrades",
    to: "orgs/enterprise_purchase_upgrades#create",
    as: :create_org_enterprise_purchase_upgrade

  constraints app_name: /actions|dependabot|codespaces|private_registries/ do
    get    "/organizations/:organization_id/settings/secrets/:app_name",                        to: "orgs/secrets_settings#index",                            as: :settings_org_secrets
    get    "/organizations/:organization_id/settings/secrets/:app_name/new",                    to: "orgs/secrets_settings#new_secret",                       as: :settings_org_secrets_new_secret
    post   "/organizations/:organization_id/settings/secrets/:app_name/new",                    to: "orgs/secrets_settings#create_secret",                    as: :settings_org_secrets_create_secret
    get    "/organizations/:organization_id/settings/secrets/:app_name/repository_items",       to: "orgs/secrets_repository_items#index",                    as: :settings_org_secrets_repository_items
    delete "/organizations/:organization_id/settings/secrets/:app_name/:name",                  to: "orgs/secrets_settings#remove_secret",                    as: :settings_org_secrets_remove_secret
    get    "/organizations/:organization_id/settings/secrets/:app_name/:name/delete",           to: "orgs/secrets_settings#remove_secret_partial",            as: :settings_org_secrets_remove_secret_partial
    get    "/organizations/:organization_id/settings/secrets/:app_name/:name",                  to: "orgs/secrets_settings#update_secret_page",               as: :settings_org_secrets_update_secret_page
    put    "/organizations/:organization_id/settings/secrets/:app_name/:name",                  to: "orgs/secrets_settings#update_secret",                    as: :settings_org_secrets_update_secret
  end

  resources :pages_protected_domains,
    only: [:new, :create, :show, :update, :destroy],
    path: "/organizations/:organization_id/settings/pages_verified_domains",
    as: :settings_org_pages_protected_domains,
    constraints: { id: /[^\/]+/ } do
  end

  # Redirects to support previous actions secrets routes.
  get    "/organizations/:organization_id/settings/secrets",                        to: redirect("/organizations/%{organization_id}/settings/secrets/actions")
  get    "/organizations/:organization_id/settings/secrets/new",                    to: redirect("/organizations/%{organization_id}/settings/secrets/actions/new")
  get    "/organizations/:organization_id/settings/secrets/:name/delete",           to: redirect("/organizations/%{organization_id}/settings/secrets/actions/%{name}/delete")
  get    "/organizations/:organization_id/settings/secrets/:name",                  to: redirect("/organizations/%{organization_id}/settings/secrets/actions/%{name}")

  get    "/organizations/:organization_id/settings/security",                                   to: "orgs/security_settings#index",                           as: :settings_org_security
  get    "/organizations/:organization_id/settings/deploy_keys",                                to: "orgs/deploy_keys#index",                                 as: :settings_org_deploy_keys
  put    "/organizations/:organization_id/settings/deploy_keys",                                to: "orgs/deploy_keys#update",                                as: :settings_org_deploy_keys_update
  patch "/organizations/:organization_id/settings/ssh_certificate_authority",
    to: "ssh_certificate_authority_owner_settings#update",
    as: :org_security_ssh_certificate_authority_owner_settings
  put    "/organizations/:organization_id/settings/two_factor_enforcement",                     to: "orgs/two_factor_enforcements#update",                    as: :settings_org_two_factor_enforcement_update
  get    "/organizations/:organization_id/settings/two_factor_enforcement_status",              to: "orgs/two_factor_enforcements#show",                      as: :settings_org_two_factor_enforcement_status
  put    "/organizations/:organization_id/settings/saml_provider",                              to: "orgs/saml_provider#update",                              as: :settings_org_saml_provider
  delete "/organizations/:organization_id/settings/saml_provider",                              to: "orgs/saml_provider#delete"
  get    "/organizations/:organization_id/settings/saml_provider/recovery_codes",               to: "orgs/saml_provider#recovery_codes",                      as: :settings_org_saml_provider_recovery_codes
  put    "/organizations/:organization_id/settings/saml_provider/regenerate_recovery_codes",    to: "orgs/saml_provider#regenerate_recovery_codes",           as: :settings_org_saml_provider_regenerate_recovery_codes
  post   "/organizations/:organization_id/settings/saml_provider/recovery_codes/download",      to: "orgs/saml_provider#download_recovery_codes",             as: :settings_org_saml_provider_download_recovery_codes
  get    "/organizations/:organization_id/settings/saml_provider/recovery_codes/print",         to: "orgs/saml_provider#print_recovery_codes",                as: :settings_org_saml_provider_print_recovery_codes
  patch "/organizations/:organization_id/settings/ip_allowlist_enabled",
    to: "ip_allowlist_enabled#update",
    as: :settings_org_security_ip_allowlist_enabled
  patch "/organizations/:organization_id/settings/ip_allowlist_app_access_enabled",
    to: "ip_allowlist_app_access_enabled#update",
    as: :settings_org_security_ip_allowlist_app_access_enabled
  get "/organizations/:organization_id/settings/compliance_reports/:key",
    to: "compliance_reports#show",
    as: :org_compliance_report

  put    "/organizations/:organization_id/settings/security_analysis/update",                                   to: "orgs/security_analysis#update",                                   as: :settings_org_security_analysis_update
  get    "/organizations/:organization_id/settings/security_analysis/dependabot",                               to: "orgs/dependabot_repository_access#show",                          as: :settings_org_security_analysis_dependabot_show
  put    "/organizations/:organization_id/settings/security_analysis/dependabot/add_repositories",              to: "orgs/dependabot_repository_access#add_repositories",              as: :settings_org_security_analysis_dependabot_add_repositories
  put    "/organizations/:organization_id/settings/security_analysis/dependabot/remove_repositories",           to: "orgs/dependabot_repository_access#remove_repositories",           as: :settings_org_security_analysis_dependabot_remove_repositories
  put    "/organizations/:organization_id/settings/security_analysis/dependabot/set_default_repository_access", to: "orgs/dependabot_repository_access#set_default_repository_access", as: :settings_org_security_analysis_dependabot_set_default_repository_access
  put    "/organizations/:organization_id/settings/security_analysis/dependabot/set_allowed_repositories",      to: "orgs/dependabot_repository_access#set_allowed_repositories",      as: :settings_org_security_analysis_dependabot_set_allowed_repositories
  get    "/organizations/:organization_id/settings/security_analysis/dependabot/suggestions",                   to: "orgs/dependabot_repository_access#suggestions",                   as: :settings_org_security_analysis_dependabot_suggestions
  get    "/organizations/:organization_id/settings/security_analysis/ghas_header",                              to: "orgs/settings/security_analysis/ghas_header#index",               as: :settings_org_security_analysis_ghas_header
  get    "/organizations/:organization_id/settings/security_analysis/ghas_repos_list/:page",                    to: "orgs/settings/security_analysis/ghas_repos#index",                as: :settings_org_security_analysis_ghas_repos_list, constraints: { page: /\d+/ }

  # Org Code Security Configurations
  get    "/organizations/:organization_id/settings/security_products",                                      to: "organizations/settings/security_products#index",               as: :settings_org_security_products
  post   "/organizations/:organization_id/settings/security_products/in_progress",                          to: "organizations/settings/security_products#in_progress",         as: :settings_org_security_products_in_progress
  get    "/organizations/:organization_id/settings/security_products/refresh",                              to: "organizations/settings/security_products#refresh",             as: :settings_org_security_products_refresh
  post   "/organizations/:organization_id/settings/security_products/dismiss_failure_banner",               to: "organizations/settings/security_products#dismiss_failure_banner", as: :settings_org_security_products_dismiss_failure_banner
  get    "/organizations/:organization_id/settings/security_products/actions_runners_labels",               to: "organizations/settings/security_products#actions_runners_labels", as: :settings_org_security_products_actions_runners_labels
  get    "/organizations/:organization_id/settings/security_products/configurations/new",                   to: "organizations/settings/security_configurations#new",           as: :settings_org_security_configurations_new
  post   "/organizations/:organization_id/settings/security_products/configurations",                       to: "organizations/settings/security_configurations#create",        as: :settings_org_security_configurations_create
  get    "/organizations/:organization_id/settings/security_products/configurations/edit/:id",              to: "organizations/settings/security_configurations#edit",          as: :settings_org_security_configurations_edit
  put    "/organizations/:organization_id/settings/security_products/configurations/:id",                   to: "organizations/settings/security_configurations#update",        as: :settings_org_security_configurations_update
  delete "/organizations/:organization_id/settings/security_products/configurations/:id",                   to: "organizations/settings/security_configurations#destroy",       as: :settings_org_security_configurations_destroy
  get    "/organizations/:organization_id/settings/security_products/configurations/view/:id",              to: "organizations/settings/security_configurations#show",          as: :settings_org_security_configurations_view

  put    "/organizations/:organization_id/settings/security_products/configuration/:id/repositories",       to: "organizations/settings/security_configuration/repositories#update",        as: :settings_org_security_configuration_repositories_update
  delete "/organizations/:organization_id/settings/security_products/configuration/repositories",           to: "organizations/settings/security_configuration/repositories#destroy",       as: :settings_org_security_configuration_repositories_destroy
  get    "/organizations/:organization_id/settings/security_products/configuration/:id/repositories_count", to: "organizations/settings/security_configurations#repositories_count", as: :settings_org_security_configurations_repositories_count

  get    "/organizations/:organization_id/settings/security_products/repositories",                         to: "organizations/settings/security_products/repositories#index",              as: :settings_org_security_products_repositories

  post   "/organizations/:organization_id/settings/security_products/repositories/advanced_security_license_summary", to: "organizations/settings/security_products/repositories#advanced_security_license_summary", as: :settings_org_security_products_repositories_advanced_security_license_summary
  post   "/organizations/:organization_id/settings/security_products/repositories/apply_confirmation_summary", to: "organizations/settings/security_products/repositories#apply_confirmation_summary", as: :settings_org_security_products_repositories_apply_confirmation_summary

  get    "/organizations/:organization_id/settings/security_products/configurations/filter-suggestions/teams",  to: "organizations/settings/security_configurations/filter_suggestions#teams", as: :settings_org_security_configurations_filter_suggestions_teams

  # Dependabot Alerts organization level rulesets
  get    "/organizations/:organization_id/settings/dependabot_rules",     to: "dependabot/dependabot_org_rules#index",     as: :settings_org_dependabot_rules
  get    "/organizations/:organization_id/settings/dependabot_rules/new", to: "dependabot/dependabot_org_rules#new",   as: :settings_org_new_dependabot_rule
  post   "/organizations/:organization_id/settings/dependabot_rules", to: "dependabot/dependabot_org_rules#create",   as: :settings_org_create_dependabot_rule
  get    "/organizations/:organization_id/settings/dependabot_rules/edit/:id", to: "dependabot/dependabot_org_rules#edit",     as: :settings_org_edit_dependabot_rule
  get    "/organizations/:organization_id/settings/dependabot_rules/edit_default/:id", to: "dependabot/dependabot_org_rules#edit_global_rule", as: :settings_org_edit_global_dependabot_rule
  put    "/organizations/:organization_id/settings/dependabot_rules/:id", to: "dependabot/dependabot_org_rules#update",     as: :settings_org_update_dependabot_rule
  put    "/organizations/:organization_id/settings/dependabot_rules/update_default/:id", to: "dependabot/dependabot_org_rules#update_global_rule", as: :settings_org_update_global_dependabot_rule
  delete "/organizations/:organization_id/settings/dependabot_rules/:id", to: "dependabot/dependabot_org_rules#destroy",     as: :settings_org_delete_dependabot_rule

  # Code Scanning organization level settings
  get "/organizations/:organization_id/settings/code_scanning/model_packs", to: "orgs/security_and_analysis/code_scanning/model_pack_settings#edit", as: :settings_org_code_scanning_model_packs
  put "/organizations/:organization_id/settings/code_scanning/model_packs",  to: "orgs/security_and_analysis/code_scanning/model_pack_settings#update", as: :settings_org_code_scanning_update_model_packs

  # Secret Scanning Push Protection

  # Delegated Bypass Reviewers
  get    "/organizations/:organization_id/settings/security_analysis/bypass_suggestions", to: "orgs/secret_scanning/push_protection/delegated_bypass_reviewers#bypass_suggestions", as: :org_secret_scanning_bypass_reviewer_suggestions

  # Secret Scanning Custom Patterns

  # Active routes
  get    "/organizations/:organization_id/settings/security_analysis/custom_patterns/new", to: "orgs/security_and_analysis/custom_patterns#new_custom_pattern", as: :settings_org_security_analysis_new_custom_pattern
  post   "/organizations/:organization_id/settings/security_analysis/custom_patterns/new", to: "orgs/security_and_analysis/custom_patterns#create_custom_pattern", as: :settings_org_security_analysis_create_custom_pattern
  delete "/organizations/:organization_id/settings/security_analysis/custom_patterns", to: "orgs/security_and_analysis/custom_patterns#delete_custom_patterns", as: :settings_org_security_analysis_delete_custom_patterns
  post   "/organizations/:organization_id/settings/security_analysis/test_custom_secret_scanning_pattern", to: "orgs/security_and_analysis/custom_patterns#test_custom_secret_scanning_pattern", as: :settings_org_security_analysis_test_custom_secret_scanning_pattern
  post   "/organizations/:organization_id/settings/security_analysis/custom_patterns/get_generated_expressions", to: "orgs/security_and_analysis/custom_patterns#get_generated_expressions", as: :settings_org_security_analysis_get_generated_expressions

  constraints id: /\d+/ do
    get    "/organizations/:organization_id/settings/security_analysis/custom_patterns/:id", to: "orgs/security_and_analysis/custom_patterns#show_custom_pattern", as: :settings_org_security_analysis_show_custom_pattern
    post   "/organizations/:organization_id/settings/security_analysis/custom_patterns/:id", to: "orgs/security_and_analysis/custom_patterns#update_custom_pattern", as: :settings_org_security_analysis_update_custom_pattern
    post   "/organizations/:organization_id/settings/security_analysis/custom_patterns/:id/settings", to: "orgs/security_and_analysis/custom_patterns#update_custom_pattern_settings", as: :settings_org_security_analysis_update_custom_pattern_settings
    delete "/organizations/:organization_id/settings/security_analysis/custom_patterns/:id", to: "orgs/security_and_analysis/custom_patterns#delete_custom_pattern", as: :settings_org_security_analysis_delete_custom_pattern
    post   "/organizations/:organization_id/settings/security_analysis/custom_patterns/:id/cancel_dry_run", to: "orgs/security_and_analysis/custom_patterns#cancel_custom_pattern_dry_run", as: :settings_org_security_analysis_cancel_custom_pattern_dry_run
    get    "/organizations/:organization_id/settings/security_analysis/get_custom_pattern_form_actions/:id", to: "orgs/security_and_analysis/custom_patterns#get_custom_pattern_form_actions", as: :settings_org_security_analysis_get_custom_pattern_form_actions
    get    "/organizations/:organization_id/settings/security_analysis/get_custom_pattern_dry_run_results_by_cursor/:id", to: "orgs/security_and_analysis/custom_patterns#get_custom_pattern_dry_run_results_by_cursor", as: :settings_org_security_analysis_get_custom_pattern_dry_run_results_by_cursor
    get    "/organizations/:organization_id/settings/security_analysis/custom_patterns/:id/metrics/alerts", to: "orgs/security_and_analysis/custom_patterns#get_alert_metrics", as: :settings_org_security_analysis_get_custom_pattern_alert_metrics
    get    "/organizations/:organization_id/settings/security_analysis/custom_patterns/:id/metrics/push_protection", to: "orgs/security_and_analysis/custom_patterns#get_push_protection_metrics", as: :settings_org_security_analysis_get_custom_pattern_push_protection_metrics
  end

  # Internal routes
  get  "/organizations/:organization_id/settings/security_analysis/custom_patterns/dry_run_repository_suggestions", to: "orgs/security_and_analysis/custom_patterns#dry_run_repository_suggestions", as: :settings_org_security_analysis_dry_run_repository_suggestions
  post  "/organizations/:organization_id/settings/security_analysis/custom_patterns/dry_run_update_selected_repositories", to: "orgs/security_and_analysis/custom_patterns#dry_run_update_selected_repositories", as: :settings_org_security_analysis_dry_run_update_selected_repositories

  # Deprecated routes - retained for redirection in case users have bookmarked.
  get    "/organizations/:organization_id/settings/security_analysis/new_custom_secret_scanning_pattern", to: redirect("/organizations/:organization_id/settings/security_analysis/custom_patterns/new")
  get    "/organizations/:organization_id/settings/security_analysis/edit_custom_secret_scanning_pattern/:id", to: redirect("/organizations/:organization_id/settings/security_analysis/custom_patterns/:id")

  get    "/organizations/:organization_id/settings/members(.:format)", to: redirect("/orgs/%{organization_id}/people")

  get    "/settings/replies",                       to: "settings/saved_replies#index",   as: :saved_replies
  post   "/settings/replies",                       to: "settings/saved_replies#create"
  put    "/settings/replies/:id",                   to: "settings/saved_replies#update"
  get    "/settings/replies/:id/edit",              to: "settings/saved_replies#edit",    as: :edit_saved_reply
  delete "/settings/replies/:id",                   to: "settings/saved_replies#destroy", as: :saved_reply
  get    "/settings/replies/assets/:user/:guid",    to: "settings/saved_reply_assets#show"

  resources :personal_reminders, except: [:edit], path: "/settings/reminders", module: :settings, param: :organization_id do
    member do
      post :reminder_test
    end
  end

  post   "/reminder_slack_workspaces/:organization_id/authorize", to: "reminder_slack_workspaces#authorize", as: :authorize_reminder_slack_workspace
  get    "/reminder_slack_workspaces/:organization_id/callback",  to: "reminder_slack_workspaces#callback",  as: :callback_reminder_slack_workspace

  get    "/settings/auth/recovery-codes",          to: "settings/auth_recovery_codes#index",                   as: :settings_auth_recovery_codes
  put    "/settings/auth/recovery-codes",          to: "settings/auth_recovery_codes#update",                  as: :settings_auth_regenerate_recovery_codes
  post   "/settings/auth/recovery-codes/download", to: "settings/auth_recovery_codes#download_recovery_codes", as: :settings_auth_download_recovery_codes
  get    "/settings/auth/recovery-codes/print",    to: "settings/auth_recovery_codes#print",                   as: :settings_auth_print_recovery_codes

  post   "/settings/migration",                                                                 to: "settings/migrations#start",                          as: :settings_user_migration_start
  post   "/settings/migration/email",                                                           to: "settings/migrations#email",                          as: :settings_user_migration_email
  get    "/settings/migration/download",                                                        to: "settings/migrations#download",                       as: :settings_user_migration_download
  delete "/settings/migration",                                                                 to: "settings/migrations#delete",                         as: :settings_user_migration_delete

  get    "/settings/export/download",            to: "settings/windbeam#download",                as: :settings_windbeam_download

  get "/settings/dotcom-user/callback", to: "settings/dotcom_users/callback#show", as: :settings_dotcom_user_callback
  get "/settings/dotcom-user", to: "settings/dotcom_users#show", as: :settings_dotcom_user
  post "/settings/dotcom-user", to: "settings/dotcom_users#create", as: :settings_dotcom_user_create
  delete "/settings/dotcom-user", to: "settings/dotcom_users#destroy", as: :settings_dotcom_user_destroy
  post "/settings/dotcom-user/change_contributions", to: "settings/dotcom_users/contributions#update", as: :settings_dotcom_user_change_contributions

  get    "/settings/enterprise-installation/:token", to: "settings/enterprise_installations#new",   as: :settings_enterprise_installation_new
  post   "/settings/enterprise-installation/:login/:token", to: "settings/enterprise_installations#create", as: :settings_enterprise_installation_create
  post   "/organizations/:organization_id/settings/enterprise_installations/stats_export", to: "settings/enterprise_installations/stats_export#create", as: :settings_enterprise_installation_stats_export
  get    "/organizations/:organization_id/settings/enterprise_installations",   to: "settings/enterprise_installations#index", as: :organization_enterprise_installations_list
  delete "/organizations/:organization_id/settings/enterprise_installations/:id",  to: "settings/enterprise_installations#destroy", as: :organization_enterprise_installation_delete

  ##
  # DismissalsController
  get     "/settings/notice-dismissals/:notice", to: "settings/dismissals#show",    as: :notice_dismissal_status
  post    "/settings/dismiss-notice/:notice",    to: "settings/dismissals#create",  as: :dismiss_notice

  ##
  # U2fRegistrationController
  post   "/u2f/registrations",                  to: "u2f_registrations#create",                as: :u2f_create
  put    "/u2f/registrations/:id",              to: "u2f_registrations#edit",                  as: :u2f_edit
  delete "/u2f/registrations/:id",              to: "u2f_registrations#destroy",               as: :u2f_destroy
  get    "/u2f/trusted_facets",                 to: "u2f_registrations#trusted_facets",        as: :u2f_trusted_facets
  get    "/u2f/login_fragment",                 to: "u2f_registrations#login_fragment",        as: :u2f_login_fragment
  post   "/u2f/trusted_devices",                to: "u2f_registrations#trusted_device_create", as: :trusted_device_create
  post   "/u2f/trusted_devices/nickname_check", to: "u2f_registrations#nickname_check",        as: :trusted_device_nickname_check

  ##
  # User Settings
  get     "/settings/avatars",      to: "avatars#show"
  get     "/settings/avatars/:id",  to: "avatars#show",  as: :settings_user_avatar
  post    "/settings/avatars/:id",  to: "avatars#update"

  get     "/settings/connections/:id", to: "oauth_accesses#show", id: /\d+/

  get     "/settings/connections/applications",             to: redirect("/settings/applications")
  get     "/settings/connections/applications/:client_id",  to: "oauth_authorizations#show",       as: :settings_oauth_authorization, client_id: AUTHORIZATION_KEY_REGEX
  delete  "/settings/connections/applications/:client_id",  to: "oauth_authorizations#destroy", client_id: AUTHORIZATION_KEY_REGEX

  post    "/settings/connections/applications/:client_id/report", to: "oauth_authorizations#report", as: :report_oauth_authorization, client_id: AUTHORIZATION_KEY_REGEX
  post    "/settings/connections/applications/revoke_all",  to: "oauth_authorizations#revoke_all", as: :revoke_all_settings_oauth_authorizations

  get     "/settings/developers", to: "settings/oauth_applications#index", as: :settings_user_developer_applications

  get     "/settings/tokens",                 to: "oauth_tokens#index",      as: :settings_user_tokens
  get     "/settings/tokens/new",             to: "oauth_tokens#new",        as: :new_settings_user_token
  post    "/settings/tokens",                 to: "oauth_tokens#create"
  get     "/settings/tokens/:id",             to: "oauth_tokens#show",       as: :settings_user_token
  put     "/settings/tokens/:id",             to: "oauth_tokens#update"
  get     "/settings/tokens/:id/regenerate",  to: "oauth_tokens#regenerate_edit", as: :regenerate_edit_settings_user_token
  post    "/settings/tokens/:id/regenerate",  to: "oauth_tokens#regenerate", as: :regenerate_settings_user_token
  delete  "/settings/tokens/:id",             to: "oauth_tokens#destroy"
  post    "/settings/tokens/revoke_all",      to: "oauth_tokens#revoke_all", as: :revoke_all_settings_user_tokens
  delete  "/settings/tokens/:id/authorizations/:org", to: "oauth_tokens#remove_authorization", as: :settings_user_token_authorization
  put     "/settings/pinned_api_version",     to: "pinned_api_versions#update", as: :pinned_api_version

  scope path: "/settings/tokens/:id", controller: "oauth_tokens/organization/credential_authorizations" do
    get "/organization_credential_authorizations", action: :index, as: :settings_user_token_organization_credential_authorizations
  end

  scope path: "/settings/personal-access-tokens" do
    scope controller: "personal_access_tokens" do
      get "/", action: :index, as: :settings_user_access_tokens
      get "/new", action: :new, as: :new_settings_user_access_token
      post "/", action: :create, as: :create_user_access_token
      get "/suggestions/(:id)", action: :suggestions, as: :user_access_token_suggestions
      get "/select-access", action: :select_access, as: :user_access_token_select_access
      post "/check-name", controller: "personal_access_tokens/check_name", action: :index, as: :token_check_name
      post "/preview-grant-request-reason", action: :preview_grant_request_reason, as: :preview_grant_request_reason

      scope path: "/:id" do
        get "/",                        action: :show,                 as: :settings_user_access_token
        get "/expiration",              action: :expiration,           as: :settings_user_access_token_expiration
        get "/regenerate",              action: :regenerate_edit,      as: :edit_regenerate_user_access_token
        post "/regenerate",             action: :regenerate,           as: :regenerate_user_access_token
        put "/",                        action: :update
        delete "/",                     action: :destroy

        scope path: "/grant-requests", controller: "personal_access_tokens/grant_requests" do
          scope path: "/organizations/:organization" do
            post "/",         action: :create,  as: :settings_user_access_request_org_access
            delete "/cancel", action: :destroy, as: :settings_user_access_cancel_org_access_request
          end

          post "/users/:user", action: :create, as: :settings_user_access_request_user_access
        end
      end
    end
  end

  # This lists authorizations for the authenticated user. But we kept the route for legacy purposes.
  get     "/settings/applications",                       to: "settings/oauth_authorizations#index",   as: :settings_user_applications

  get     "/settings/applications/new",                   to: "oauth_applications#new",                as: :new_settings_user_application
  post    "/settings/applications",                       to: "oauth_applications#create"
  get     "/settings/applications/:id",                   to: "oauth_applications#show",               as: :settings_user_application
  put     "/settings/applications/:id",                   to: "oauth_applications#update"
  delete  "/settings/applications/:id",                   to: "oauth_applications#destroy"
  get     "/settings/applications/:id/advanced",          to: "oauth_applications#advanced",           as: :advanced_settings_user_application
  put     "/settings/applications/:id/transfer",          to: "oauth_applications#transfer",           as: :transfer_settings_user_application
  get     "/settings/applications/:id/beta",              to: "oauth_applications#beta_features",      as: :settings_user_applications_beta_features
  post    "/settings/applications/:id/beta",              to: "apps/beta_features#enable"
  delete  "/settings/applications/:id/beta",              to: "apps/beta_features#disable"
  post    "/settings/applications/:id/revoke_all_tokens", to: "oauth_applications#revoke_all_tokens",  as: :revoke_all_tokens_settings_user_application
  post    "/settings/applications/:id/client_secret",     to: "oauth_applications#generate_client_secret", as: :generate_client_secret_settings_user_application
  delete  "/settings/applications/:id/client_secret/:secret_id", to: "oauth_applications#remove_client_secret", as: :remove_client_secret_settings_user_application
  get     "/settings/applications/:id/oauth_authorizations",     to: "oauth_applications#oauth_authorizations", as: :settings_user_applications_oauth_authorizations

  get     "/settings/codespaces",                         to: "settings/codespaces#index",                                 as: :settings_user_codespaces
  put     "/settings/codespaces/preferred_editor",        to: "settings/codespaces#update_codespace_preferred_editor",     as: :settings_user_codespaces_preferred_editor
  put     "/settings/codespaces/gpg_authorization",       to: "settings/codespaces#update_gpg_authorization",              as: :settings_user_codespaces_gpg_authorization
  put     "/settings/codespaces/expiry_notification",       to: "settings/codespaces#update_codespaces_expiry_notification", as: :settings_user_codespaces_expiry_notification
  put     "/settings/codespaces/settings_sync_authorization",       to: "settings/codespaces#update_codespaces_settings_sync_authorization", as: :settings_user_codespaces_settings_sync_authorization
  put     "/settings/codespaces/preferred_host_image",       to: "settings/codespaces#update_preferred_host_image", as: :settings_user_codespaces_preferred_host_image
  put     "/settings/codespaces/repository_authorizations",       to: "settings/codespaces#update_codespaces_repository_authorizations", as: :settings_user_codespaces_repository_authorizations
  put     "/settings/codespaces/update_trusted_repositories_access",      to: "settings/codespaces#update_trusted_repositories_access",  as: :settings_user_codespaces_update_trusted_repositories_access
  put     "/settings/codespaces/dotfiles_enabled",        to: "settings/codespaces#update_codespace_dotfiles_enabled",     as: :settings_user_codespaces_dotfiles_enabled
  put     "/settings/codespaces/update_default_location",      to: "settings/codespaces#update_default_location",  as: :settings_user_codespaces_update_default_location
  put     "/settings/codespaces/update_default_idle_timeout",  to: "settings/codespaces#update_default_idle_timeout",      as: :settings_user_codespaces_update_default_idle_timeout
  put     "/settings/codespaces/update_default_retention_period",  to: "settings/codespaces#update_default_retention_period",      as: :settings_user_codespaces_update_default_retention_period
  put     "/settings/codespaces/update_dotfiles_repository",      to: "settings/codespaces#update_dotfiles_repository",  as: :settings_user_codespaces_update_dotfiles_repository

  get     "/settings/applications/:user_id/transfers/:id",          to: "settings/oauth_application_transfers#show",          as: :settings_user_application_transfer
  delete  "/settings/applications/:user_id/transfers/:id",          to: "settings/oauth_application_transfers#destroy"
  put     "/settings/applications/:user_id/transfers/:id/accept",   to: "settings/oauth_application_transfers#accept",        as: :accept_settings_user_application_transfer

  get     "/settings/apps/",                      to: "settings/integrations#index",           as: :settings_user_apps
  get     "/settings/apps/new",                   to: "settings/integrations#new",             as: :new_settings_user_app
  post    "/settings/apps/new",                   to: "settings/integrations#receive_manifest", as: :receive_user_app_from_manifest
  get     "/settings/apps/manifest",              to: "settings/integrations#new_from_manifest", as: :new_from_manifest
  get     "/settings/apps/authorizations",        to: "settings/integrations#authorizations",  as: :settings_user_app_authorizations
  post    "/settings/apps/",                      to: "settings/integrations#create"
  get     "/settings/apps/:id",                   to: "settings/integrations#show",            as: :settings_user_app
  get     "/settings/apps/:id/permissions",       to: "settings/integrations#permissions",     as: :settings_user_app_permissions
  get     "/settings/apps/:id/installations",     to: "settings/integrations#installations",   as: :settings_user_app_installations
  get     "/settings/apps/:id/advanced",          to: "settings/integrations#advanced",        as: :settings_user_app_advanced
  get     "/settings/apps/:id/beta",              to: "settings/integrations#beta_features",   as: :settings_user_app_beta_features
  put     "/settings/apps/:id/beta-toggle",       to: "settings/integrations#beta_toggle",     as: :settings_user_app_beta_feature_toggle
  get     "/settings/apps/:id/copilot",           to: "settings/integrations#copilot",         as: :settings_user_app_copilot
  put     "/settings/apps/:id/copilot",           to: "settings/integrations#update_copilot",  as: :settings_user_app_update_copilot
  post    "/settings/apps/:id/sign_agreement",         to: "settings/integrations#sign_agreement",  as: :settings_user_app_sign_agreement
  get     "/integrations/:id/hovercard",          to: "hovercards/integrations#show",          as: :integrations_hovercard

  resources :pages_protected_domains,
    only: [:new, :create, :show, :update, :destroy],
    path: "/settings/pages_verified_domains",
    as: :settings_pages_protected_domains,
    constraints: { id: /[^\/]+/ } do
  end

  resources :ip_allowlist_entries,
    as: "settings_user_apps_ip_allowlist_entries",
    path: "/settings/apps/:integration_id/ip_allowlist_entries",
    only: %w(new create edit update destroy),
    controller: "ip_allowlist_entries"

  resource :interaction_limits,
    as: :settings_interaction_limits,
    path: "/settings/interaction_limits",
    only: [:show, :update],
    module: :settings

  constraints(guid: WEBHOOK_GUID_REGEX, id: WEBHOOK_REGEX, hook_id: /\d+/) do
    get  "/settings/apps/:app_id/hooks/:hook_id/deliveries",                     to: "hook_deliveries#index",     as: :settings_user_app_hook_deliveries, context: "integration"
    get  "/settings/apps/:app_id/hooks/:hook_id/deliveries/:id",                 to: "hook_deliveries#show",      as: :settings_user_app_hook_delivery, context: "integration"
    get  "/settings/apps/:app_id/hooks/:hook_id/deliveries/:id/payload.:format", to: "hook_deliveries#payload",   as: :settings_user_app_hook_delivery_payload, format: "json", context: "integration"
    get  "/settings/apps/:app_id/hooks/:hook_id/redeliveries",                     to: "hook_deliveries#redeliveries",     as: :settings_user_app_hook_redeliveries, context: "integration"
    post "/settings/apps/:app_id/hooks/:hook_id/deliveries/:guid/redeliver",       to: "hook_deliveries#redeliver", as: :settings_user_app_redeliver_hook_delivery, context: "integration"
  end
  put     "/settings/apps/:id",                   to: "settings/integrations#update"
  put     "/settings/apps/:id/permissions",       to: "settings/integrations#update_permissions", as: :update_permissions_settings_user_app
  post    "/settings/apps/:id/key",               to: "settings/integrations#generate_key",    as: :generate_key_settings_user_app
  delete  "/settings/apps/:id/key/:key_id",       to: "settings/integrations#remove_key",      as: :remove_key_settings_user_app
  get     "/settings/apps/:id/keys",              to: "settings/integrations#keys",            as: :list_keys_settings_user_app
  put     "/settings/apps/:id/public",            to: "settings/integrations#make_public",     as: :make_public_settings_user_app
  put     "/settings/apps/:id/private",          to: "settings/integrations#make_private",   as: :make_private_settings_user_app
  post    "/settings/apps/:id/revoke_all_tokens", to: "settings/integrations#revoke_all_tokens", as: :revoke_all_tokens_settings_user_app
  post    "/settings/apps/:id/client_secret",      to: "settings/integrations#generate_client_secret", as: :generate_client_secret_settings_user_app
  delete  "/settings/apps/:id/client_secret/:secret_id", to: "settings/integrations#remove_client_secret", as: :remove_client_secret_settings_user_app
  delete  "/settings/apps/:id",                   to: "settings/integrations#destroy"
  put     "/settings/apps/:id/transfer",          to: "settings/integrations#transfer",        as: :transfer_settings_user_app
  get     "/settings/apps/:id/transfer_suggestions", to: "settings/integrations#transfer_suggestions", as: :transfer_settings_user_app_suggestions

  post    "/settings/apps/preview_note", to: "settings/integrations#preview_note", as: :preview_permissions_note_user_app

  get     "/settings/apps/transfers/:id",        to: "settings/integration_transfers#show",   as: :settings_user_app_transfer
  delete  "/settings/apps/transfers/:id",        to: "settings/integration_transfers#destroy"
  put     "/settings/apps/transfers/:id/accept", to: "settings/integration_transfers#accept", as: :accept_settings_user_app_transfer

  get     "/settings/installations",                           to: "settings/installations#index",                      as: :settings_user_installations
  get     "/settings/installations/:id",                       to: "settings/installations#show",                       as: :settings_user_installation
  put     "/settings/installations/:id/update",                to: "settings/installations#update",                     as: :update_settings_user_installation
  delete  "/settings/installations/:id",                       to: "settings/installations#destroy"
  get     "/settings/installations/:id/permissions/update",    to: "settings/installations#permissions_update_request", as: :permissions_update_request_settings_user_installation
  put     "/settings/installations/:id/permissions/update",    to: "settings/installations#update_permissions",         as: :update_permissions_settings_user_installation
  get     "/settings/installations/:id/repositories",          to: "settings/installations#repositories",               as: :settings_user_installation_repositories
  post    "/settings/installations/:id/suspended",             to: "settings/installations#suspend",                    as: :suspend_settings_user_installation
  delete  "/settings/installations/:id/suspended",             to: "settings/installations#unsuspend",                  as: :unsuspend_settings_user_installation

  resources :secrets, only: [:new, :create, :edit, :update, :destroy], param: :name, controller: "settings/codespaces/secrets", path: "/settings/codespaces/secrets", as: :codespaces_user_secrets, name: CODESPACE_SECRET_NAME_REGEX

  ##
  # Org Settings
  get     "/organizations/:organization_id/settings/applications/transfers/:id",          to: "orgs/oauth_application_transfers#show",    as: :settings_org_application_transfer
  delete  "/organizations/:organization_id/settings/applications/transfers/:id",          to: "orgs/oauth_application_transfers#destroy"
  put     "/organizations/:organization_id/settings/applications/transfers/:id/accept",   to: "orgs/oauth_application_transfers#accept",  as: :accept_settings_org_application_transfer

  get     "/organizations/:organization_id/settings/apps/transfers/:id",                  to: "orgs/integration_transfers#show",          as: :settings_org_app_transfer
  delete  "/organizations/:organization_id/settings/apps/transfers/:id",                  to: "orgs/integration_transfers#destroy"
  put     "/organizations/:organization_id/settings/apps/transfers/:id/accept",           to: "orgs/integration_transfers#accept",        as: :accept_settings_org_app_transfer

  get     "/organizations/:organization_id/settings/member_privileges",                   to: "orgs/settings/member_privileges#index",    as: :settings_org_member_privileges
  get     "/organizations/:organization_id/settings/security_analysis",                   to: "orgs/settings/security_analysis#index",    as: :settings_org_security_analysis
  resources :organizations, only: [], module: :orgs do
    namespace :settings do
      namespace :security_analysis do
        resources :pattern_configurations, only: [:index] do
          collection do
            patch :update
          end
        end
      end
    end
  end
  get     "/organizations/:organization_id/settings/security_analysis/ghas_settings",     to: "orgs/settings/ghas_settings#index",        as: :settings_org_security_analysis_ghas_settings
  # Organization Roles
  get     "/organizations/:organization_id/settings/org_roles",                           to: "orgs/org_roles#index",                     as: :settings_org_roles
  post    "/organizations/:organization_id/settings/org_roles",                           to: "orgs/org_roles#create"
  get     "/organizations/:organization_id/settings/org_roles/new",                       to: "orgs/org_roles#new",                       as: :new_settings_org_roles
  get     "/organizations/:organization_id/settings/org_roles/:id/edit",                  to: "orgs/org_roles#edit",                      as: :edit_settings_org_roles
  put     "/organizations/:organization_id/settings/org_roles/:id/update",                to: "orgs/org_roles#update",                    as: :update_settings_org_roles
  delete  "/organizations/:organization_id/settings/org_roles/:id",                       to: "orgs/org_roles#destroy",                   as: :delete_settings_org_roles
  get     "/organizations/:organization_id/settings/org_roles/new/fgp_metadata",          to: "orgs/org_roles#fgp_metadata",              as: :settings_org_roles_fgp_metadata

  # Organization policy rulesets
  get    "/organizations/:organization_id/settings/policies/repositories",                                to: "orgs/repository_policies#ruleset_index",  as: :settings_org_repository_policies
  get    "/organizations/:organization_id/settings/policies/repositories/new",                            to: "orgs/repository_policies#ruleset_new"
  get    "/organizations/:organization_id/settings/policies/repositories/:id/history",                    to: "orgs/repository_policies#ruleset_history_summary"
  get    "/organizations/:organization_id/settings/policies/repositories/:id/history/:history_id/compare(/:compare_history_id)", to: "orgs/repository_policies#ruleset_history_comparison"
  get    "/organizations/:organization_id/settings/policies/repositories/:id/history/:history_id/view",   to: "orgs/repository_policies#ruleset_history_view",         as: :organization_view_repository_policy_history
  post   "/organizations/:organization_id/settings/policies/repositories/validate_value/:type",           to: "orgs/repository_policies#ruleset_validate_value"
  get    "/organizations/:organization_id/settings/policies/repositories/:id/bypass_suggestions",         to: "orgs/repository_policies#ruleset_bypass_suggestions"
  get    "/organizations/:organization_id/settings/policies/repositories/available_properties",           to: "orgs/repository_policies#ruleset_available_properties"
  get    "/organizations/:organization_id/settings/policies/repositories/:id/repo_suggestions",           to: "orgs/repository_policies#ruleset_repo_suggestions"
  get    "/organizations/:organization_id/settings/policies/repositories/:id",                            to: "orgs/repository_policies#ruleset_show",                 as: :edit_organization_repository_policy
  post   "/organizations/:organization_id/settings/policies/repositories/:id",                            to: "orgs/repository_policies#ruleset_update",               as: :set_organization_repository_policy
  delete "/organizations/:organization_id/settings/policies/repositories/:id",                            to: "orgs/repository_policies#ruleset_destroy",              as: :delete_organization_repository_policy
  get    "/organizations/:organization_id/policies/repositories/:id",                                     to: "orgs/view_repository_policies#ruleset_show",                 as: :view_organization_repository_policy

  # Organization Role Assignments
  get     "/organizations/:organization_id/settings/org_role_assignments",                to: "orgs/org_role_assignments#index",          as: :settings_org_role_assignments
  get     "/organizations/:organization_id/settings/org_role_assignments/new",                to: "orgs/org_role_assignments#new",          as: :settings_org_role_assignments_new
  delete  "/organizations/:organization_id/settings/org_role_assignments/:actor_type/:actor_id/:role_id",                to: "orgs/org_role_assignments#destroy",          as: :delete_org_role_assignments
  post    "/organizations/:organization_id/settings/org_role_assignments",                to: "orgs/org_role_assignments#create",         as: :add_org_role_assignment
  get     "/organizations/:organization_id/settings/assignment_suggestions",              to: "orgs/org_role_assignments#suggestions",    as: :org_role_assignment_suggestions

  # Organization Role Assignment Queries
  get     "/organizations/:organization_id/settings/org_role_assignment_queries",                to: "orgs/org_role_assignment_queries#index",          as: :settings_org_role_assignment_queries

  # Repository Roles
  get     "/organizations/:organization_id/settings/roles",                               to: "orgs/repo_roles#repository_roles",              as: :settings_org_repository_roles
  post    "/organizations/:organization_id/settings/roles",                               to: "orgs/repo_roles#create"
  get     "/organizations/:organization_id/settings/roles/new",                           to: "orgs/repo_roles#new",                           as: :new_settings_org_repository_roles
  get     "/organizations/:organization_id/settings/roles/fgps",                          to: "orgs/repo_roles#fgps",                          as: :settings_org_fgps
  get     "/organizations/:organization_id/settings/roles/:id/permission_list",           to: "orgs/repo_roles#permission_list",               as: :role_permission_list
  get     "/organizations/:organization_id/settings/roles/:id/edit",                      to: "orgs/repo_roles#edit",                          as: :edit_settings_org_repository_roles
  put     "/organizations/:organization_id/settings/roles/:id/update",                    to: "orgs/repo_roles#update",                        as: :update_settings_org_repository_roles
  delete  "/organizations/:organization_id/settings/roles/:id",                           to: "orgs/repo_roles#destroy",                       as: :delete_settings_org_repository_roles
  get     "/organizations/:organization_id/settings/roles/new/fgp_metadata",              to: "orgs/repo_roles#fgp_metadata",                  as: :settings_org_fgp_metadata
  get     "/organizations/:organization_id/settings/teams",                               to: "orgs/settings/teams#index",                as: :settings_org_teams
  post    "/organizations/:organization_id/settings/migrate_legacy_admin_teams",          to: "orgs/settings/legacy_admin_teams_migration#create", as: :settings_org_migrate_legacy_admin_teams

  put     "/organizations/:organization_id/settings/projects/links/reorder",              to: "orgs/memex_project_links#reorder",         as: :settings_org_memex_project_links_reorder
  post    "/organizations/:organization_id/settings/projects/links",                      to: "orgs/memex_project_links#create",          as: :settings_org_memex_project_links
  get     "/organizations/:organization_id/settings/projects/links",                      to: "orgs/memex_project_links#show"
  get     "/organizations/:organization_id/settings/projects",                            to: "orgs/settings/projects#index",             as: :settings_org_projects

  get    "/organizations/:organization_id/settings/deleted_repositories",                 to: "orgs/settings/deleted_repositories#index", as: :settings_org_deleted_repositories

  get     "/organizations/:organization_id/settings/domains",                             to: "verifiable_domains#index",                 as: :settings_org_domains

  get "/organizations/:organization_id/settings/import-export", to: "orgs/settings/import_export/mannequins#index", as: :settings_org_import_export
  get "/organizations/:organization_id/settings/import-export/attribution-invitations", to: "orgs/settings/import_export/attribution_invitations#index", as: :settings_org_import_export_invitations

  get     "/organizations/:organization_id/settings/oauth_application_policy/confirm",    to: "orgs/oauth_application_policy#splash",      as: :oauth_application_policy_confirm

  get     "/organizations/:organization_id/settings/audit-log",                           to: "orgs/audit_log#index",                      as: :settings_org_audit_log
  get     "/organizations/:organization_id/settings/audit-log/results",                   to: "orgs/audit_log#results",                    as: :settings_org_audit_log_results
  get     "/organizations/:organization_id/settings/audit-log/suggestions",               to: "orgs/audit_log#suggestions",                as: :settings_org_audit_log_suggestions

  get     "/organizations/:organization_id/settings/hooks",                               to: "organization_hooks#index",                  as: :organization_hooks
  post    "/organizations/:organization_id/settings/hooks",                               to: "organization_hooks#create"
  get     "/organizations/:organization_id/settings/hooks/new",                           to: "organization_hooks#new",                    as: :new_organization_hook
  get     "/organizations/:organization_id/settings/hooks/:id",                           to: "organization_hooks#show",                   as: :organization_hook
  put     "/organizations/:organization_id/settings/hooks/:id",                           to: "organization_hooks#update"
  delete  "/organizations/:organization_id/settings/hooks/:id",                           to: "organization_hooks#destroy"

  scope path: "/organizations/:organization_id/settings/personal-access-tokens" do
    scope controller: "orgs/settings/third_party_access/personal_access_tokens" do
      get     "/",                  action: :index,             as: :settings_org_personal_access_tokens
      get     "/active",            action: :active,            as: :settings_org_active_personal_access_tokens
      get     "/toolbar_actions",   action: :toolbar_actions,   as: :settings_org_personal_access_tokens_toolbar_actions
      delete  "/",                  action: :bulk_destroy,      as: :settings_org_bulk_destroy_personal_access_tokens

      scope path: "/filters" do
        get "/owners",       action: :index, as: :settings_org_personal_access_token_owners_filter,       controller: "orgs/settings/third_party_access/personal_access_tokens/owners"
        get "/repositories", action: :index, as: :settings_org_personal_access_token_repositories_filter, controller: "orgs/settings/third_party_access/personal_access_tokens/repositories"
        get "/permissions", action: :index, as: :settings_org_personal_access_token_permissions_filter, controller: "orgs/settings/third_party_access/personal_access_tokens/permissions"
      end

      scope path: "/:id" do
        get    "/", action: :show,   as: :settings_org_personal_access_token
        delete "/", action: :destroy

        scope controller: "orgs/settings/third_party_access/personal_access_tokens/credential_expirations" do
          get "/credential-expiration", action: :show, as: :settings_org_personal_access_token_credential_expiration
        end

        scope controller: "orgs/settings/third_party_access/personal_access_tokens/repository_selection" do
          get "/repositories", action: :index, as: :settings_org_personal_access_token_repositories
        end
      end
    end

    scope controller: "orgs/settings/third_party_access/personal_access_tokens/restrict_access" do
      patch "/restrict-access", action: :update, as: :settings_org_restrict_pat_access
    end

    scope controller: "orgs/settings/third_party_access/personal_access_tokens/restrict_legacy_access" do
      patch "/restrict-legacy-access", action: :update, as: :settings_org_restrict_legacy_pat_access
    end
  end

  scope path: "/organizations/:organization_id/settings/personal-access-tokens-onboarding", controller: "orgs/settings/third_party_access/personal_access_tokens/onboarding" do
    get   "/", action: :edit, as: :settings_org_personal_access_tokens_onboarding
    patch "/", action: :update
  end

  scope controller: "orgs/settings/third_party_access/personal_access_tokens/maximum_lifetimes" do
    patch "/organizations/:organization_id/settings/personal-access-tokens/maximum-lifetime", action: :update, as: :settings_org_personal_access_tokens_maximum_lifetimes
  end

  scope path: "/organizations/:organization_id/settings/personal-access-token-requests" do
    scope controller: "orgs/settings/third_party_access/personal_access_token_requests" do
      get "/",                  action: :index,             as: :settings_org_personal_access_token_requests
      get "/toolbar_actions",   action: :toolbar_actions,   as: :settings_org_personal_access_token_requests_toolbar_actions
      put  "/",                 action: :bulk_approve,      as: :settings_org_bulk_approve_personal_access_token_requests
      delete  "/",              action: :bulk_deny,         as: :settings_org_bulk_deny_personal_access_token_requests

      scope path: "/filters" do
        get "/owners", action: :index, as: :settings_org_personal_access_token_request_owners_filter, controller: "orgs/settings/third_party_access/personal_access_token_requests/owners"
      end

      scope path: "/:id" do
        get "/",        action: :show,    as: :settings_org_personal_access_token_request
        delete "/",     action: :deny,    as: :settings_org_personal_access_token_request_deny
        put "/approve", action: :approve, as: :settings_org_personal_access_token_request_approve

        scope controller: "orgs/settings/third_party_access/personal_access_token_requests/credential_expirations" do
          get "/credential-expiration", action: :show, as: :settings_org_personal_access_token_request_credential_expiration
        end

        scope controller: "orgs/settings/third_party_access/personal_access_token_requests/repository_selection" do
          get "/repositories", action: :index, as: :settings_org_personal_access_token_request_repositories
        end
      end
    end

    scope controller: "orgs/settings/third_party_access/personal_access_token_requests/auto_approve" do
      patch "/auto-approve", action: :update, as: :settings_org_auto_approve_personal_access_token_requests
    end
  end

  scope path: "/organizations/:organization_id/settings/network_configurations", controller: "orgs/settings/network_configurations" do
    get "/", action: :index, as: :settings_org_network_configurations
    get "/azure_private_network/new", action: :new_private_network, as: :settings_org_network_configurations_new_private_network
    put "/azure_private_network/new", action: :validate_private_network, as: :settings_org_network_configurations_validate_private_network
    get "/find", action: :find, as: :settings_org_network_configurations_find
    get "/:network_configuration_id", action: :show, as: :settings_org_network_configurations_show
    get "/:network_configuration_id/edit", action: :edit, as: :settings_org_network_configurations_edit
    post "/update", action: :update, as: :settings_org_network_configurations_update
    delete "/remove", action: :remove, as: :settings_org_network_configurations_remove
  end

  constraints(guid: WEBHOOK_GUID_REGEX, id: WEBHOOK_REGEX, hook_id: /\d+/) do
    get  "/organizations/:organization_id/settings/hooks/:hook_id/deliveries",                     to: "hook_deliveries#index",     as: :organization_hook_deliveries
    get  "/organizations/:organization_id/settings/hooks/:hook_id/deliveries/:id",                 to: "hook_deliveries#show",      as: :organization_hook_delivery
    get  "/organizations/:organization_id/settings/hooks/:hook_id/deliveries/:id/payload.:format", to: "hook_deliveries#payload",   as: :organization_hook_delivery_payload, format: "json"
    get  "/organizations/:organization_id/settings/hooks/:hook_id/redeliveries",                     to: "hook_deliveries#redeliveries",     as: :organization_hook_redeliveries
    post "/organizations/:organization_id/settings/hooks/:hook_id/deliveries/:guid/redeliver",       to: "hook_deliveries#redeliver", as: :organization_redeliver_hook_delivery
  end

  resources :reminders, except: [:edit], path: "/organizations/:organization_id/settings/reminders", module: :orgs, as: :org_reminders do
    collection do
      get :team_autocomplete
      get :repository_suggestions
    end
    member do
      post :reminder_test
    end
  end

  if GitHub.enterprise?
    post   "/organizations/:organization_id/settings/hooks/:id/update_pre_receive",        to: "organization_hooks#update_pre_receive",     as: :update_organization_pre_receive
  end

  get     "/organizations/:organization_id/settings/apps/",                       to: "orgs/integrations#index",                   as: :settings_org_apps
  get     "/organizations/:organization_id/settings/apps/new",                    to: "orgs/integrations#new",                     as: :new_settings_org_app
  post    "/organizations/:organization_id/settings/apps/new",                    to: "orgs/integrations#receive_manifest",       as: :new_settings_org_app_from_manifest
  post    "/organizations/:organization_id/settings/apps/",                       to: "orgs/integrations#create"
  get     "/organizations/:organization_id/settings/apps/:id",                    to: "orgs/integrations#show",                    as: :settings_org_app
  get     "/organizations/:organization_id/settings/apps/:id/permissions",        to: "orgs/integrations#permissions",             as: :settings_org_app_permissions
  get     "/organizations/:organization_id/settings/apps/:id/installations",      to: "orgs/integrations#installations",           as: :settings_org_app_installations
  get     "/organizations/:organization_id/settings/apps/:id/advanced",           to: "orgs/integrations#advanced",                as: :settings_org_app_advanced
  get     "/organizations/:organization_id/settings/apps/:id/beta",               to: "orgs/integrations#beta_features",           as: :settings_org_app_beta_features
  put     "/organizations/:organization_id/settings/apps/:id/beta-toggle",        to: "orgs/integrations#beta_toggle",             as: :settings_org_app_beta_feature_toggle
  get     "/organizations/:organization_id/settings/apps/:id/copilot",            to: "orgs/integrations#copilot",                 as: :settings_org_app_copilot
  put     "/organizations/:organization_id/settings/apps/:id/copilot",            to: "orgs/integrations#update_copilot",          as: :settings_org_app_update_copilot
  post    "/organizations/:organization_id/settings/apps/:id/sign_agreement",     to: "orgs/integrations#sign_agreement",          as: :settings_org_app_sign_agreement

  resources :ip_allowlist_entries,
    as: "settings_org_apps_ip_allowlist_entries",
    path: "organizations/:organization_id/settings/apps/:integration_id/ip_allowlist_entries",
    only: %w(new create edit update destroy),
    controller: "ip_allowlist_entries"

  constraints(guid: WEBHOOK_GUID_REGEX, id: WEBHOOK_REGEX, hook_id: /\d+/) do
    get  "/organizations/:organization_id/settings/apps/:app_id/hooks/:hook_id/deliveries",                     to: "hook_deliveries#index",     as: :settings_org_app_hook_deliveries, context: "integration"
    get  "/organizations/:organization_id/settings/apps/:app_id/hooks/:hook_id/deliveries/:id",                 to: "hook_deliveries#show",      as: :settings_org_app_hook_delivery, context: "integration"
    get  "/organizations/:organization_id/settings/apps/:app_id/hooks/:hook_id/deliveries/:id/payload.:format", to: "hook_deliveries#payload",   as: :settings_org_app_hook_delivery_payload, format: "json", context: "integration"
    get  "/organizations/:organization_id/settings/apps/:app_id/hooks/:hook_id/redeliveries",                     to: "hook_deliveries#redeliveries",     as: :settings_org_app_hook_redeliveries, context: "integration"
    post "/organizations/:organization_id/settings/apps/:app_id/hooks/:hook_id/deliveries/:guid/redeliver",       to: "hook_deliveries#redeliver", as: :settings_org_app_redeliver_hook_delivery, context: "integration"
  end

  put     "/organizations/:organization_id/settings/apps/:id",                    to: "orgs/integrations#update"
  put     "/organizations/:organization_id/settings/apps/:id/permissions",        to: "orgs/integrations#update_permissions",      as: :update_permissions_settings_org_app
  post    "/organizations/:organization_id/settings/apps/:id/key",                to: "orgs/integrations#generate_key",            as: :generate_key_settings_org_app
  delete  "/organizations/:organization_id/settings/apps/:id/key/:key_id",        to: "orgs/integrations#remove_key",              as: :remove_key_settings_org_app
  get     "/organizations/:organization_id/settings/apps/:id/keys",               to: "orgs/integrations#keys",                    as: :list_keys_settings_org_app
  put     "/organizations/:organization_id/settings/apps/:id/public",             to: "orgs/integrations#make_public",             as: :make_public_settings_org_app
  put     "/organizations/:organization_id/settings/apps/:id/private",           to: "orgs/integrations#make_private",           as: :make_private_settings_org_app
  post    "/organizations/:organization_id/settings/apps/:id/revoke_all_tokens",  to: "orgs/integrations#revoke_all_tokens",       as: :revoke_all_tokens_settings_org_app
  post    "/organizations/:organization_id/settings/apps/:id/client_secret",      to: "orgs/integrations#generate_client_secret",  as: :generate_client_secret_settings_org_app
  delete  "/organizations/:organization_id/settings/apps/:id/client_secret/:secret_id", to: "orgs/integrations#remove_client_secret", as: :remove_client_secret_settings_org_app
  delete  "/organizations/:organization_id/settings/apps/:id",                    to: "orgs/integrations#destroy"
  put     "/organizations/:organization_id/settings/apps/:id/transfer",           to: "orgs/integrations#transfer",                as: :transfer_settings_org_app
  get     "/organizations/:organization_id/settings/apps/:id/transfer_suggestions",   to: "orgs/integrations#transfer_suggestions", as: :transfer_settings_org_app_suggestions

  post    "/organizations/:organization_id/settings/apps/preview_note", to: "settings/integrations#preview_note", as: :preview_permissions_note_org_app

  get     "/organizations/:organization_id/settings/publisher/",                          to: "orgs/publisher_verification#publisher",                   as: :settings_org_publisher
  post     "/organizations/:organization_id/settings/publisher/request_verification",      to: "orgs/publisher_verification#apply_verification",           as: :settings_org_verify_publisher
  post     "/organizations/:organization_id/settings/publisher/cancel_verification",      to: "orgs/publisher_verification#cancel_verification",           as: :settings_org_cancel_publisher_verification

  get     "/organizations/:organization_id/settings/installations",                           to: "orgs/installations#index",                      as: :settings_org_installations
  get     "/organizations/:organization_id/settings/installations/:id",                       to: "orgs/installations#show",                       as: :settings_org_installation
  put     "/organizations/:organization_id/settings/installations/:id/update",                to: "orgs/installations#update",                     as: :update_settings_org_installation
  delete  "/organizations/:organization_id/settings/installations/:id",                       to: "orgs/installations#destroy"
  get     "/organizations/:organization_id/settings/installations/:id/permissions/update",    to: "orgs/installations#permissions_update_request", as: :permissions_update_request_settings_org_installation
  put     "/organizations/:organization_id/settings/installations/:id/permissions/update",    to: "orgs/installations#update_permissions",         as: :update_permissions_settings_org_installation
  get     "/organizations/:organization_id/settings/installations/:id/repositories",          to: "orgs/installations#repositories",               as: :settings_org_installation_repositories
  post    "/organizations/:organization_id/settings/installations/:id/suspended",             to: "orgs/installations#suspend",                    as: :suspend_settings_org_installation
  delete  "/organizations/:organization_id/settings/installations/:id/suspended",             to: "orgs/installations#unsuspend",                  as: :unsuspend_settings_org_installation

  # FGP Manage Organization owned GitHub App
  get     "/organizations/:organization_id/settings/permissions/integrations/:id/managers",       to: "orgs/permissions/integrations#managers",           as: :settings_org_permissions_integrations_managers
  get     "/organizations/:organization_id/settings/permissions/integrations/:id/suggestions",    to: "orgs/permissions/integrations#suggestions",        as: :settings_org_permissions_integrations_managers_suggestions
  post    "/organizations/:organization_id/settings/permissions/integrations/:id/grant",          to: "orgs/permissions/integrations#grant",              as: :settings_org_permissions_integrations_managers_grant
  delete  "/organizations/:organization_id/settings/permissions/integrations/:id/revoke",         to: "orgs/permissions/integrations#revoke",             as: :settings_org_permissions_integrations_managers_revoke

  # FGP Manage *all* Organization owned GitHub Apps
  get     "/organizations/:organization_id/settings/permissions/manage_integrations/suggestions", to: "orgs/permissions/manage_integrations#suggestions", as: :settings_org_permissions_manage_integrations_suggestions
  post    "/organizations/:organization_id/settings/permissions/manage_integrations/grant",       to: "orgs/permissions/manage_integrations#grant",       as: :settings_org_permissions_manage_integrations_grant
  delete  "/organizations/:organization_id/settings/permissions/manage_integrations/revoke",      to: "orgs/permissions/manage_integrations#revoke",      as: :settings_org_permissions_manage_integrations_revoke

  delete  "/organizations/:organization_id/settings/connections/:id",                     to: "oauth_accesses#destroy"

  get     "/organizations/:organization_id/settings/applications",                        to: "oauth_applications#index",                  as: :settings_org_applications
  get     "/organizations/:organization_id/settings/applications/new",                    to: "oauth_applications#new",                    as: :new_settings_org_application
  post    "/organizations/:organization_id/settings/applications",                        to: "oauth_applications#create"
  get     "/organizations/:organization_id/settings/applications/:id",                    to: "oauth_applications#show",                   as: :settings_org_application
  put     "/organizations/:organization_id/settings/applications/:id",                    to: "oauth_applications#update"
  delete  "/organizations/:organization_id/settings/applications/:id",                    to: "oauth_applications#destroy"
  get     "/organizations/:organization_id/settings/applications/:id/advanced",           to: "oauth_applications#advanced",               as: :advanced_settings_org_application
  put     "/organizations/:organization_id/settings/applications/:id/transfer",           to: "oauth_applications#transfer",               as: :transfer_settings_org_application
  get     "/organizations/:organization_id/settings/applications/:id/beta",               to: "oauth_applications#beta_features",          as: :settings_org_applications_beta_features
  post    "/organizations/:organization_id/settings/applications/:id/beta",               to: "apps/beta_features#enable"
  delete  "/organizations/:organization_id/settings/applications/:id/beta",               to: "apps/beta_features#disable"
  post    "/organizations/:organization_id/settings/applications/:id/revoke_all_tokens",  to: "oauth_applications#revoke_all_tokens",      as: :revoke_all_tokens_settings_org_application
  post    "/organizations/:organization_id/settings/applications/:id/client_secret",      to: "oauth_applications#generate_client_secret", as: :generate_client_secret_settings_org_application
  delete  "/organizations/:organization_id/settings/applications/:id/client_secret/:secret_id", to: "oauth_applications#remove_client_secret", as: :remove_client_secret_settings_org_application
  get     "/organizations/:organization_id/settings/applications/:id/oauth_authorizations",     to: "oauth_applications#oauth_authorizations", as: :settings_org_applications_oauth_authorizations

  get     "/organizations/:organization_id/settings/interaction_limits",                  to: "orgs/settings/interaction_limits#show",     as: :org_interaction_limits
  put     "/organizations/:organization_id/settings/interaction_limits",                  to: "orgs/settings/interaction_limits#update",   as: :update_org_interaction_limits

  # "Repository defaults" settings page
  get    "/organizations/:organization_id/settings/repository-defaults",                  to: "orgs/repository_default_settings#index",            as: :settings_org_repo_defaults
  get    "/organizations/:organization_id/settings/labels", to: redirect("/organizations/%{organization_id}/settings/repository-defaults"), format: false

  # OrganizationRulesBypassRequestsController
  get   "/organizations/:organization_id/settings/rules/bypass_requests",                 to: "orgs/organization_rules_bypass_requests#index",                      as: :organization_rules_bypass_requests
  get   "/organizations/:organization_id/settings/rules/bypass_requests/requesters",      to: "orgs/organization_rules_bypass_requests#bypass_request_requesters",  as: :organization_rules_bypass_request_requesters
  get   "/organizations/:organization_id/settings/rules/bypass_requests/approvers",       to: "orgs/organization_rules_bypass_requests#bypass_request_approvers",   as: :organization_rules_bypass_request_approvers
  get   "/organizations/:organization_id/settings/rules/bypass_requests/repo_suggestions", to: "orgs/code_rulesets#ruleset_repo_suggestions"

  # "Repository policies" settings page
  get    "/organizations/:organization_id/settings/rules",                                to: "orgs/code_rulesets#ruleset_index",                as: :organization_rulesets
  get    "/organizations/:organization_id/settings/rules/insights",                       to: "orgs/code_rulesets#rule_insights",             as: :organization_rule_insights
  get    "/organizations/:organization_id/settings/rules/insights/actors",                to: "orgs/code_rulesets#rule_insights_actors",      as: :organization_rule_insights_actors
  get    "/organizations/:organization_id/settings/rules/insights/repo_suggestions",      to: "orgs/code_rulesets#ruleset_repo_suggestions"
  get    "/organizations/:organization_id/settings/rules/new",                            to: "orgs/code_rulesets#ruleset_new",                  as: :new_organization_ruleset
  get    "/organizations/:organization_id/settings/rules/:id/history",                    to: "orgs/code_rulesets#ruleset_history_summary"
  get    "/organizations/:organization_id/settings/rules/:id/history/:history_id/compare(/:compare_history_id)", to: "orgs/code_rulesets#ruleset_history_comparison"
  get    "/organizations/:organization_id/settings/rules/:id/history/:history_id/view",   to: "orgs/code_rulesets#ruleset_history_view",         as: :organization_view_ruleset_history
  post   "/organizations/:organization_id/settings/rules/validate_value/:type",           to: "orgs/code_rulesets#ruleset_validate_value",       as: :organization_ruleset_value_validation
  post   "/organizations/:organization_id/settings/rules/validate_import",        to: "orgs/code_rulesets#ruleset_validate_import"
  get    "/organizations/:organization_id/settings/rules/integration_suggestions",        to: "orgs/code_rulesets#ruleset_integration_suggestions"
  get    "/organizations/:organization_id/settings/rules/:id/required_reviewer_suggestions",  to: "orgs/code_rulesets#ruleset_required_reviewer_suggestions"
  get    "/organizations/:organization_id/settings/rules/:id/bypass_suggestions",         to: "orgs/code_rulesets#ruleset_bypass_suggestions"
  get    "/organizations/:organization_id/settings/rules/:id/export_ruleset/:history_id", to: "orgs/code_rulesets#export_ruleset"
  get    "/organizations/:organization_id/settings/rules/:id/export_ruleset",             to: "orgs/code_rulesets#export_ruleset"
  get    "/organizations/:organization_id/settings/rules/workflows",                      to: "orgs/code_rulesets#get_workflows_content"
  get    "/organizations/:organization_id/settings/rules/available_properties",           to: "orgs/code_rulesets#ruleset_available_properties"
  get    "/organizations/:organization_id/settings/rules/:id/repo_suggestions",           to: "orgs/code_rulesets#ruleset_repo_suggestions"
  post   "/organizations/:organization_id/settings/rules/deferred_target_counts",         to: "orgs/code_rulesets#ruleset_deferred_target_counts"
  get    "/organizations/:organization_id/settings/rules/:id",                            to: "orgs/code_rulesets#ruleset_show",                 as: :organization_ruleset
  post   "/organizations/:organization_id/settings/rules/:id",                            to: "orgs/code_rulesets#ruleset_update",               as: :set_organization_ruleset
  delete "/organizations/:organization_id/settings/rules/:id",                            to: "orgs/code_rulesets#ruleset_destroy",              as: :delete_organization_ruleset

  # Repository groups
  get    "/organizations/:organization_id/groups",                                        to: "orgs/groups#index",                         as: :organization_groups
  get    "/organizations/:organization_id/settings/groups",                               to: "orgs/group_settings#index",                 as: :organization_group_settings
  get    "/organizations/:organization_id/settings/groups/new",                           to: "orgs/group_settings#new"
  post   "/organizations/:organization_id/settings/groups/new",                           to: "orgs/group_settings#create"
  get    "/organizations/:organization_id/settings/groups/suggestions/access_permissions", to: "orgs/group_settings#access_permissions_suggestions"
  get    "/organizations/:organization_id/settings/groups/suggestions/repositories",      to: "orgs/group_settings#repository_suggestions"
  get    "/organizations/:organization_id/settings/groups/:group_id",                     to: "orgs/group_settings#show"
  post   "/organizations/:organization_id/settings/groups/:group_id",                     to: "orgs/group_settings#create"
  put    "/organizations/:organization_id/settings/groups/:group_id",                     to: "orgs/group_settings#update"
  delete "/organizations/:organization_id/settings/groups/:group_id",                     to: "orgs/group_settings#delete"
  get    "/organizations/:organization_id/settings/groups/:group_id/repositories",        to: "orgs/group_settings#group_repositories"

  # Repository commit signoff settings for an org
  put    "/organizations/:organization_id/settings/commit-signoff",                       to: "orgs/commit_signoff_settings#update",               as: :update_org_signoff_settings

  # Property definitions for an org
  get    "/organizations/:organization_id/settings/custom-properties",                          to: "orgs/custom_properties_settings#index",             as: :org_custom_properties
  post   "/organizations/:organization_id/settings/custom-properties",                          to: "orgs/custom_properties_settings#create",            as: :org_custom_properties_create, format: :json
  post   "/organizations/:organization_id/settings/custom-properties/values",                   to: "orgs/custom_properties_settings#update_repos_properties", as: :org_custom_properties_update_repos_properties, format: :json
  get    "/organizations/:organization_id/settings/custom-property/(:property_name)",           to: "orgs/custom_properties_settings#show",              as: :org_custom_properties_show
  delete "/organizations/:organization_id/settings/custom-property/:property_name",           to: "orgs/custom_properties_settings#destroy",           as: :org_custom_properties_destroy
  get    "/organizations/:organization_id/settings/custom-properties-usage/:property_name",     to: "orgs/custom_properties_settings#check_usage",       as: :org_custom_properties_usage
  get    "/organizations/:organization_id/settings/custom-properties/list-repos-values",                   to: "orgs/custom_properties_settings#list_repos_property_values",       as: :org_custom_properties_repos_property_values

  # Label defaults for an org
  get    "/organizations/:organization_id/settings/labels/preview/:name",                 to: "orgs/label_settings#preview",                       as: :preview_org_label
  post    "/organizations/:organization_id/settings/labels",                              to: "orgs/label_settings#create",                        as: :org_user_labels
  put    "/organizations/:organization_id/settings/labels/:id",                           to: "orgs/label_settings#update",                        as: :delete_org_user_label
  delete    "/organizations/:organization_id/settings/labels/:id",                        to: "orgs/label_settings#destroy",                       as: :update_org_user_label

  # Repository default branch setting for an org
  put    "/organizations/:organization_id/settings/default-branch",                       to: "orgs/default_branch_settings#update",               as: :update_org_default_branch

  # Org Email Verification
  scope "/organizations/:organization_id" do
    resources :emails, controller: "user_emails", only: [:create], as: :organization_emails
    match "/emails/:id/confirm_verification/:t", controller: "user_emails", action: :confirm_verification, as: :organization_confirm_verification_email, format: false, via: [:get, :post]
    match "/emails/:id/confirm_verification",    controller: "user_emails", action: :confirm_verification, format: false, via: [:get, :post]

    resources :profile_emails, controller: "orgs/organization_profile_emails", only: [:create] do
      member do
        post :resend_verification_request
      end
    end
    match "/profile_emails/:id/confirm_verification/:t", controller: "orgs/organization_profile_emails", action: :confirm_verification, as: :organization_confirm_profile_email, format: false, via: [:get, :post]
  end

  if GitHub.oauth_application_policies_enabled?
    get     "/organizations/:organization_id/settings/oauth_application_policy",            to: "orgs/oauth_application_policy#show",        as: :settings_org_oauth_application_policy
  end

  get "/users/:user_id/contributions", to: "user_contributions#show", as: :user_contributions
  get "/users/:user_id/contributions/sample", to: "user_contributions#sample", as: :user_contributions_sample
  get "/users/:user_id/organizations_info", to: "users#organizations_info", as: :user_organizations_info
  get "/users/:user_id/tab_counts", to: "profiles#tab_counts", as: :user_tab_counts

  post "/users/survey_developer_tools", to: "users#record_developer_tools_survey_popup_shown", as: :record_developer_tools_survey_popup_shown

  put "/users/:user_id/emails/primary", to: "user_emails#set_primary", as: :set_primary_user_email
  put "/users/:user_id/emails/backup", to: "user_emails#set_backup", as: :set_backup_user_email

  # User account succession
  get "/users/:user_id/succession/invitation", to: "successor_invitations#show_pending", as: :pending_successor_invitation
  post "/users/:user_id/succession/invitation/accept", to: "successor_invitations#accept", as: :successor_invitation_accept
  post "/users/:user_id/succession/invitation/decline", to: "successor_invitations#decline", as: :successor_invitation_decline
  post "/succession/set_successor", to: "successor_invitations#create", as: :set_successor
  put  "/succession/unset_successor", to: "successor_invitations#revoke", as: :unset_successor
  put  "/succession/cancel", to: "successor_invitations#cancel", as: :cancel_successor_invitation
  get  "/succession/suggestions", to: "successor_invitations#suggestions", as: :user_successor_suggestions

  ##
  # Reactions
  put "/users/:user_id/reactions", to: "reactions#update", as: :update_reaction

  ##
  # Org announcement banners
  get    "/organizations/:organization_id/settings/announcement", to: "orgs/settings/announcement#announcement", as: :edit_org_announcement
  put    "/organizations/:organization_id/settings/preview_announcement", to: "orgs/settings/announcement#preview_announcement", as: :org_announcement_preview
  patch  "/organizations/:organization_id/settings/announcement", to: "orgs/settings/announcement#set_announcement", as: :org_set_announcement
  delete "/organizations/:organization_id/settings/announcement", to: "orgs/settings/announcement#destroy", as: :org_destroy_announcement

  ##
  # Resources
  resources :users, only: [] do
    member do
      post :rename
      delete :dismiss_notice
      delete :dismiss_repository_notice
      put :set_private_contributions_preference
      put :set_activity_overview_preference, controller: "settings/profiles", action: :update_activity_overview_enabled
      put :set_profile_badges_preference, controller: "settings/profiles", action: :update_profile_badges_preference
    end

    resources :emails, controller: "user_emails" do
      member do
        post :request_verification
      end

      collection do
        put :toggle_visibility
        put :toggle_email_visibility_warning
      end
    end

    resource :search, only: [:show], module: :users

    unless GitHub.enterprise?
      resources :staff_access_requests, only: [:show], controller: "users/staff_access_requests" do
        member do
          put :accept
          put :deny
        end
      end
    end

    match "/emails/:id/confirm_verification/:t", controller: "user_emails", action: :confirm_verification, as: :confirm_verification_email, format: false, via: [:get, :post]
    match "/emails/:id/confirm_verification",    controller: "user_emails", action: :confirm_verification, format: false, via: [:get, :post]

    unless GitHub.single_or_multi_tenant_enterprise?
      match "/emails/:id/request_claim",        controller: "user_emails", action: :request_claim,     as: :request_claim_email,     format: false, via: [:post]
      match "/emails/:id/cancel_claim_request", controller: "user_emails", action: :cancel_claim_request, as: :cancel_email_claim_request, format: false, via: [:post]
      match "/emails/:id/confirm_claim",        controller: "user_emails", action: :confirm_claim,     as: :confirm_claim_email,     format: false, via: [:post]
      match "/emails/:id/mark_as_unclaimed",    controller: "user_emails", action: :mark_as_unclaimed, as: :mark_email_as_unclaimed, format: false, via: [:post]
    end

    collection do
      get  :index, as: false
      post :create, as: false
    end

    new do
      get  :new
    end

    member do
      get :edit
      put :update, as: :user
      delete :destroy, as: false
    end
  end

  post "/topics/:topic_name/star", to: "topics/stars#create", as: :star_topic
  delete "/topics/:topic_name/unstar", to: "topics/stars#destroy", as: :unstar_topic

  resource :my_bio, only: :update, controller: :bios

  put "/users/:user_id/set_pinned_items",     to: "profile_pins#set_pinned_items", as: :user_set_pinned_items
  put "/users/:user_id/reorder_pinned_items", to: "profile_pins#reorder_pinned_items", as: :user_reorder_pinned_items
  get "/users/:user_id/pinned_items_modal",   to: "profile_pins#pinned_items_modal", as: :user_pinned_items_modal
  get "/users/:user_id/pinnable_items",       to: "profile_pins#pinnable_items", as: :user_pinnable_items

  post "/users/:user_id/pinned_feeds", to: "pinned_feeds#create", as: :create_pinned_feed
  delete "/users/:user_id/pinned_feeds/:pinned_feed_id", to: "pinned_feeds#destroy", as: :destroy_pinned_feed

  if GitHub.blog_enabled?
    get "/blog", to: redirect("#{GitHub.blog_url}/")
    get "/blog/broadcasts", to: redirect("#{GitHub.blog_url}/broadcasts/")
    get "/blog/subscribe", to: redirect("#{GitHub.blog_url}/subscribe/")
    get "/blog/category/:category", to: redirect("#{GitHub.blog_url}/category/%{category}/")
    get "/blog/:category.atom", to: redirect("#{GitHub.blog_url}/%{category}.atom"), as: :category_feed, format: "atom"
    get "/updates", to: redirect(GitHub.blog_url)
    get "/updates/satellite-2016", to: redirect(GitHub.blog_url)

    get "/blog/:id", to: "blog_redirects#show"
  end

  ##
  # Codespaces
  ##
  post "codespaces/survey/dismiss", to: "codespaces/survey#dismiss", as: :codespaces_survey_dismiss
  post "codespaces/survey/open",    to: "codespaces/survey#open",    as: :codespaces_survey_open
  resources :codespaces, param: :identifier, constraints: { identifier: CODESPACE_REGEX }, except: [:edit] do
    member do
      post   "export", as: :export
      post   "suspend", as: :suspend
      get    "exported", as: :exported
      get    "export_control", as: :export_control
      get    "provisioned", as: :provisioned
      get    "provisioned_vscode", as: :provisioned_vscode
      get    "published", as: :published
    end

    collection do
      get  "repository_select", as: :repository_select
      get  "skus", as: :skus
      get  "trusted_repository_select", as: :trusted_repository_select
      get  "dotfiles_repository_select", as: :dotfiles_repository_select
      post "toggle_dev_flags", as: :toggle_dev_flags
      get  "badge.svg", action: :badge, as: :badge
      get  "templates", as: :templates

      get  "auth/:identifier", to: "codespaces/auth#port_forwarding", as: :auth_port_forwarding
      get  "auth", to: "codespaces/auth#passthru", as: :auth_redirect
      get  "launch/:identifier", to: "codespaces/auth#passthru", as: :auth_launch
      post ":identifier/cascade_token", to: "codespaces/auth#mint_cascade_token", as: :mint_cascade_token
      post "allow_permissions", as: :allow_permissions
      get "allow_settings_sync", as: :allow_settings_sync
      post "update_settings_sync", as: :update_settings_sync
      get  "close_window_prompt", as: :close_window_prompt
      get  "prebuild_availability", as: :prebuild_availability
      scope "new/:user_id/:repository", constraints: { repository: REPO_REGEX, user_id: USERID_REGEX } do
        get "/", to: "codespaces#new", as: :new_with_nwo # Repo NWO routing
        get "pull/:pull_id", to: "codespaces#new", pull_id: /\d+/, as: :new_with_pull # Repo NWO + pull/:number
        get "tree/*name(/*path)", to: "codespaces#new", name: /.+/, as: :new_with_branch # Repo NWO + tree routing
      end
    end
  end

  if Rails.env.development? && ENV["CODESPACES"]
    get "/port_visibility_check", to: "codespaces/auth#port_visibility_check"
  end

  ##
  # Redirects for template slugs like codespace.new/:slug
  ##
  get "/codespaces/new/:slug", to: redirect("/codespaces/new?template=%{slug}")

  ##
  # Redirects to support previous codespaces routes
  ##
  constraints(owner: USERID_REGEX, name: CODESPACE_REGEX) do
    get    "/codespaces/:owner/:name/provisioned", to: redirect("/codespaces/%{name}/provisioned")
    post   "/codespaces/:owner/:name/cascade_token", to: redirect("/codespaces/%{name}/cascade_token")
    get    "/codespaces/:owner/:name", to: redirect("/codespaces/%{name}")
    delete "/codespaces/:owner/:name", to: redirect("/codespaces/%{name}")
  end

  ## Insights
  resources :insights, only: [] do
    collection do
      # /insights/insights_auth_and_config
      get :insights_auth_and_config
    end
  end

  ##
  # Repositories
  resources :repositories, only: [:index, :create] do
    collection do
      get "search", to: redirect("/search")
    end
  end

  post "/repositories/check-name", to: "repositories#check_name", as: :repository_check_name
  get "/repositories/transfers/:token", to: "account#accept_repository_transfer_request", as: :repository_transfer

  # Sub Dependencies
  get "/repositories/network/sub_dependencies", to: "network#sub_dependencies", as: :network_sub_dependencies

  # Commit badges
  get "/commits/badges", to: "commit_badges#index", as: :commit_badges

  # PR review decisions
  get "/pull_request_review_decisions", to: "pull_request_review_decisions#index"

  ##
  # Guides
  get "/guides/pages",                                                   to: redirect("https://pages.github.com")
  get "/guides/textile-formatting",                                      to: redirect("http://textile.thresholdstate.com/")
  get "/guides/addressing-authentication-problems-with-ssh",             to: redirect("#{GitHub.help_url}/troubleshooting-ssh")
  get "/guides/how-to-not-have-to-type-your-password-for-every-push",    to: redirect("#{GitHub.help_url}/working-with-key-passphrases")
  get "/guides/local-github-config",                                     to: redirect("#{GitHub.help_url}/git-email-settings/")
  get "/guides/the-github-api",                                          to: redirect("#{GitHub.help_url}/api/")
  get "/guides/understanding-deploy-keys",                               to: redirect("#{GitHub.help_url}/deploy-keys/")
  get "/guides/deploying-with-capistrano",                               to: redirect("#{GitHub.help_url}/capistrano")
  get "/guides/issues-with-textmate-set-as-git-editor",                  to: redirect("#{GitHub.help_url}/textmate/")
  get "/guides/managing-multiple-clients-and-their-repositories",        to: redirect("#{GitHub.help_url}/managing-clients/")
  get "/guides/multiple-github-accounts",                                to: redirect("#{GitHub.help_url}/managing-clients/")
  get "/guides/fork-a-project-and-submit-your-modifications",            to: redirect("#{GitHub.help_url}/forking/")
  get "/guides/keeping-a-git-fork-in-sync-with-the-forked-repo",         to: redirect("#{GitHub.help_url}/forking/")
  get "/guides/how-do-i-delete-a-repository",                            to: redirect("#{GitHub.help_url}/deleting-a-repo/")
  get "/guides/change-author-details-in-commit-history",                 to: redirect("#{GitHub.help_url}/changing-author-info/")
  get "/guides/completely-remove-a-file-from-all-revisions",             to: redirect("#{GitHub.help_url}/removing-sensitive-data")
  get "/guides/changing-a-series-of-commits-or-patches",                 to: redirect("#{GitHub.help_url}/rebase")
  get "/guides/remove-a-remote-branch",                                  to: redirect("#{GitHub.help_url}/remotes")
  get "/guides/push-a-branch-to-github",                                 to: redirect("#{GitHub.help_url}/remotes")
  get "/guides/copy-a-remote-branch",                                    to: redirect("#{GitHub.help_url}/remotes")
  get "/guides/rename-a-remote-branch",                                  to: redirect("#{GitHub.help_url}/remotes")
  get "/guides/ignore-for-git",                                          to: redirect("#{GitHub.help_url}/git-ignore")
  get "/guides/push-tags-to-github",                                     to: redirect("#{GitHub.help_url}/remotes/")
  get "/guides/dealing-with-errors-when-pushing",                        to: redirect("#{GitHub.help_url}/remotes/")
  get "/guides/changing-your-origin",                                    to: redirect("#{GitHub.help_url}/remotes/")
  get "/guides/import-an-existing-git-repo",                             to: redirect("#{GitHub.help_url}/remotes/")
  get "/guides/disaster-faq-what-to-do-when-github-goes-bad",            to: redirect("http://ozmm.org/posts/when_github_goes_down.html")
  get "/guides/providing-your-ssh-key",                                  to: redirect("#{GitHub.help_url}/key-setup-redirect")
  get "/guides/git-screencasts",                                         to: redirect("https://gist.github.com/423320")
  get "/guides/git-podcasts",                                            to: redirect("https://gist.github.com/423320")
  get "/guides/feature-requests",                                        to: redirect(GitHub.contact_support_url)
  get "/guides/github-bugs",                                             to: redirect(GitHub.contact_support_url)
  get "/guides/setting-up-a-remote-repository-using-github-and-osx",     to: redirect("#{GitHub.help_url}/")
  get "/guides/using-git-and-github-for-the-windows-for-newbies",        to: redirect("#{GitHub.help_url}/")
  get "/guides/i-m-missing-my-gravatar-icon-on-my-commits",              to: redirect("#{GitHub.help_url}/troubleshooting-common-issues/")
  get "/guides/get-git-on-mac",                                          to: redirect("#{GitHub.help_url}/mac-git-installation")
  get "/guides/compiling-git-on-os-x-leopard",                           to: redirect("#{GitHub.help_url}/mac-git-installation")
  get "/guides/compiling-and-installing-git-on-mac-os-x",                to: redirect("#{GitHub.help_url}/mac-git-installation")
  get "/guides/rebase-howto",                                            to: redirect("#{GitHub.help_url}/rebase/")
  get "/guides/syntax-highlighting-isn-t-working-for-my-language",       to: redirect("#{GitHub.help_url}/troubleshooting-common-issues/")
  get "/guides/how-to-move-a-repo-to-another-account",                   to: redirect("#{GitHub.help_url}/moving-a-repo")
  get "/guides/tell-git-your-user-name-and-email-address",               to: redirect("#{GitHub.help_url}/git-email-settings")
  get "/guides/dealing-with-newlines-in-git",                            to: redirect("#{GitHub.help_url}/dealing-with-lineendings")
  get "/guides/using-the-egit-eclipse-plugin-with-github",               to: redirect("https://wiki.eclipse.org/EGit/User_Guide")
  get "/guides/how-to-clone-from-github-with-ssh-tunnels",               to: redirect("#{GitHub.help_url}/firewalls-and-proxies/")
  get "/guides/dealing-with-firewalls-and-proxies",                      to: redirect("#{GitHub.help_url}/firewalls-and-proxies/")
  get "/guides/how-to-transparently-clone-from-github-with-ssh-tunnels", to: redirect("#{GitHub.help_url}/firewalls-and-proxies/")
  get "/guides/import-from-subversion",                                  to: redirect("#{GitHub.help_url}/svn-importing")
  get "/guides/put-your-git-branch-name-in-your-shell-prompt",           to: redirect("http://www.gitready.com/advanced/2009/01/23/bash-git-status.html")
  get "/guides/pull-requests",                                           to: redirect("#{GitHub.help_url}/pull-requests")
  get "/guides/git-cheat-sheet",                                         to: redirect("#{GitHub.help_url}/git-cheat-sheets")
  get "/guides/readme-formatting",                                       to: redirect("https://github.com/github/markup/blob/master/README.md")
  get "/guides/developing-with-submodules",                              to: redirect("#{GitHub.help_url}/submodules/")
  get "/guides",                                                         to: redirect(GitHub.help_url)
  get "/support-enterprise",                                             to: redirect("#{GitHub.help_url}/en/github/working-with-github-support/about-github-support")

  get "/plans", to: redirect("/pricing")

  # Help
  get "/help", to: redirect(GitHub.help_url)

  # Repos Preferences
  put   "/repos/preferences",           to: "repos_expand_preferences#update"

  # Regex validation
  post  "/repos/validate_regex/:type",  to: "regex_validation#validate_regex"

  # suggestions
  get  "suggestions(/:subject_type(/:subject_id))", to: "suggestions#show", as: :suggestions

  # Attribution Invitiations
  put "/attribution-invitations/:id/accept", to: "attribution_invitations#accept", as: :accept_attribution_invitation
  put "/attribution-invitations/:id/reject", to: "attribution_invitations#reject", as: :reject_attribution_invitation

  ##
  # PagesAuthController
  # Pages auth call should not be within the scope of the repo for security reasons.
  get  "pages/auth",                    to: "pages_auth#authenticate",   as: :authorize_page_id

  ##
  # Standalone Patch and Diff URLs
  # Must be above the repo scope to avoid matching "raw" as owner
  scope repository: REPO_REGEX, path: "/raw/:user_id/:repository", format: false do
    get "/pull/:id.diff",  controller:  "patch_diff", action: "raw_diff",  id: /.+/, as: :pull_request_raw_diff
    get "/pull/:id.patch", controller:  "patch_diff", action: "raw_patch", id: /.+/, as: :pull_request_raw_patch
  end

  ##
  # AzureExpLocalAssignmentsController
  # view and update exp assignments.
  # Must be above repo scope to avoid matching FilesController rules
  resources :azure_exp_local_assignments, only: [:show], except: [:edit, :update], param: :user, controller: "azure_exp_local_assignments" do
    collection do
      get :edit
      put :update
    end
  end


  #
  # Canonical URL for fetching user avatar with user database id
  # Here :user_database_id is used instead of :user_id since :user_id is used as `login` in this file
  #

  get "/user_avatars/:user_database_id", to: "user_avatars#show", as: :user_avatar

  #
  # Repository routes
  #
  # Everything in this block is scoped under /:user_id/:repository. All repo
  # routes should be placed in here.
  #
  scope "/:user_id/:repository", constraints: { repository: REPO_REGEX, user_id: USERID_REGEX } do
    ##
    # Retired Features
    get "forkqueue",     to: redirect("/410")
    get "graphs/impact", to: redirect("/410")

    if GitHub.enterprise?
      get    "(/*gopkgpath)", to: "repositories#go_metatag", as: :go_tag, constraints: { query_string: "go-get=1" }
    end

    ##
    # Repositories survey
    unless GitHub.enterprise?
      get "repos/survey", to: "repos/survey#index", as: :repos_survey
      post "repos/survey/dismiss", to: "repos/survey#dismiss", as: :repos_survey_dismiss
      post "repos/survey/answer", to: "repos/survey#answer", as: :repos_survey_answer
    end

    ##
    # Code Nav survey
    unless GitHub.enterprise?
      get "repos/code_nav_survey", to: "repos/code_nav_survey#index", as: :repos_code_nav_survey
      post "repos/code_nav_survey/answer", to: "repos/code_nav_survey#answer", as: :repos_code_nav_survey_answer
    end

    # Copilot Label Recommendations
    get   "label_recommendations", to: "repos/label_recommendations#index", id: /\d+/,  as: :repo_label_recommendations

    ##
    # Repository import
    scope "import" do
      scope "auth" do
        put "", to: "repository_imports/auth#update", as: :repository_import_auth
      end

      scope "authors" do
        get "", to: "repository_imports/authors#index", as: :repository_import_authors
        get "suggestions", to: "repository_imports/authors#author_suggestions", as: :repository_import_author_suggestions
        put ":id", to: "repository_imports/authors#update", as: :repository_import_author
      end

      scope "large_files" do
        get "", to: "repository_imports/large_files#index", as: :repository_import_large_files
        put "", to: "repository_imports/large_files#update"
      end

      scope "project" do
        put "", to: "repository_imports/project#update", as: :repository_import_project
      end

      get "", to: "repository_imports#show", as: :repository_import
      patch "", to: "repository_imports#update"
      delete "", to: "repository_imports#destroy"
    end

    ##
    # Milestones
    get    "milestones",                     to: "milestones#index", as: :milestones
    get    "milestones/paginate",            to: "milestones#paginate_milestones", as: :paginate_milestones
    get    "milestones/new",                 to: "milestones#new", as: :new_milestone
    post   "milestones",                     to: "milestones#create"
    get    "milestones/:id/edit",            to: "milestones#edit", as: :edit_milestone
    put    "milestones/:id/toggle",          to: "milestones#toggle"
    put    "milestone/:id",                  to: "milestones#update"
    put    "milestone/:id/prioritize",       to: "milestones#prioritize", as: :prioritize_milestone
    delete "milestone/:id",                  to: "milestones#destroy"
    get    "milestone/:number",              to: "milestones#show", as: :milestone
    get    "milestone/:id/issues",           to: "milestones#issues", as: :milestone_issues
    get    "milestone/:id/paginated_issues", to: "milestones#paginated_issues", as: :milestone_paginated_issues
    # Legacy route
    get    "milestones/:milestone_name",  to: "issues#index", milestone_name: /.+/, legacy: true, as: :milestone_query

    get    "projects",                                to: "repos/projects#index", as: :repo_projects, constraints: -> (request) { request.query_parameters[:type] == "classic" }
    get    "projects",                                to: redirect(status: 307) { |params, request|
      query_params = request.query_parameters
      new_params = query_params.except(:type)
      "/#{params[:user_id]}/#{params[:repository]}/projects#{new_params.empty? ? "" : "?#{new_params.to_param}"}"
    }, as: false, constraints: -> (request) { %w[beta new].include?(request.query_parameters[:type]) }
    get    "projects",                                to: "repos/memexes#index", as: :repo_projects_beta

    delete "projects/beta/unlink(/:memex_project_id)",  to: "repos/memexes#unlink", as: :unlink_repo_project_beta
    put    "projects/beta/upsert",                      to: "repos/memexes#upsert_repo_project",  as: :upsert_repo_project_beta
    get    "projects/beta/suggestions/projects",        to: "repos/memexes#projects_suggestions", as: :repo_project_beta_suggestions
    get    "projects/:number/edit",                   to: "repos/projects#edit", as: :edit_repo_project
    get    "projects/:number",                        to: "repos/projects#show", as: :repo_project
    delete "projects",                                to: "repos/projects#destroy"
    put    "projects/:number",                        to: "repos/projects#update"
    put    "projects/:number/state",                  to: "repos/projects#update_state", as: :update_repo_project_state
    get    "projects/:number/search_results",         to: "repos/projects#search_results", as: :repo_project_search_results
    get    "projects/:number/target_owner_results",   to: "repos/projects#target_owner_results", as: :repo_project_target_owner_results
    get    "projects/:number/activity",               to: "repos/projects#activity", as: :repo_project_activity
    get    "projects/:number/add_cards_link",         to: "repos/projects#add_cards_link", as: :repo_project_add_cards_link
    post   "projects/:number/clone",                  to: "repos/projects#clone", as: :repo_project_clone
    post   "projects/:number/migrate",                to: "repos/projects#migrate", as: :repo_project_migrate
    delete   "projects/:number/dismiss_notice", to: "repos/projects#dismiss_notice", as: :repo_dismiss_project_notice
    get    "projects/:number/migration_status",       to: "repos/projects#migration_status_notice_partial", as: :repo_project_migration_status_notice_partial

    put    "projects/issues/:issue_number",                       to: "project_issues#update", as: :repo_project_issues
    post   "projects/issues",                                     to: "project_issues#new", as: :new_repo_project_issues
    get    "projects/issues/projects_suggestions",  to: "project_issues#projects_suggestions", as: :projects_suggestions

    # Reactions for subjects owned by repositories
    put    "reactions", to: "reactions#update", as: :update_repository_reaction, context: "repository"

    # Needs to be available even when GitHub Actions is disabled for GHES setup
    get "actions", to: "actions#index", as: :actions

    # Packages
    if PackageRegistryHelper.show_packages?
      get "packages", to: "registry/packages#index", as: :packages
      get "packages/:id", to: "registry/packages#show", as: :package
      get "packages/:id/:version_id/edit", to: "registry/packages#edit", as: :edit_package_version
      post "packages/:id/:version_id/edit", to: "registry/packages#commit", as: :commit_package_version
      get "packages/:id/versions", to: "registry/packages#versions", as: :package_versions
      get "packages/:id/options", to: "registry/packages#options", as: :package_options
      put "packages/:id/restore", to: "registry/packages#restore", as: :package_restore
      delete "packages/:id", to: "registry/packages#destroy", as: :destroy_package
      delete "packages/:package_id/versions/:id/destroy", to: "registry/package_versions#destroy", as: :destroy_package_version
      put "packages/:package_id/versions/:id/restore", to: "registry/package_versions#restore", as: :package_version_restore

      constraints name: /@?[\w\-\/\.%]+/ do
        get "pkgs/:ecosystem/:name/versions", to: "registry_two/package_versions#show", as: :repo_package_versions_two
        get "pkgs/:ecosystem/:name/:version", to: "registry_two/packages#show", as: :repo_package_two
        get "pkgs/:ecosystem/:name", to: "registry_two/packages#package_view", as: :repo_packages_two_view
      end
    end

    ##
    # Discussions
    draw :discussions

    ##
    # Issues
    get   "issues",                   to: "issues#index",                        as: :issues
    put   "issues/triage",            to: "issues#triage",                       as: :triage_issues

    get   "issues/new",               to: "issues#new",                          as: :new_issue
    get   "issues/new/choose",        to: "issues#choose", as: :choose_issue

    match "issues/new/show_partial",  to: "issues#show_partial",                 as: :show_partial_new_issue, via: [:get, :post]
    post  "issues",                   to: "issues#create"

    get   "issues/show_menu_content", to: "issues#show_menu_content",            as: :show_menu_content_issues

    # CloseIssueReferences - used by issues and pull requests
    put   "issues/closing_references", to: "closing_references#update", as: :closing_issue_reference
    get   "issues/closing_references/partials/sidebar", to: "closing_references#show", as: :closing_issue_references_sidebar
    get   "issues/closing_references/referencing_repositories", to: "closing_references#referencing_repositories", as: :closing_issue_references_repositories
    get   "issues/closing_references/:source_id(/:repository_id)", to: "closing_references#index", repository_id: /\d+/, as: :closing_issue_references

    get    "issues/:id/tracked_in/hovercard", to: "hovercards/issue_links#tracked_in", id: /\d+/
    get    "issues/:id/tracking/:tracked_id/hovercard", to: "hovercards/issue_links#tracking", id: /\d+/, tracked_id: /\d+/

    get   "issues/:id",               to: "issues#show",          id: /\d+/,  as: :issue
    put   "issues/:id",               to: "issues#update",        id: /\d+/
    delete "issues/:id",              to: "issues#destroy",       id: /\d+/, as: :delete_issue

    get   "issues/:id/linked_closing_reference", to: "issues#linked_closing_reference", as: "linked_closing_reference"
    get   "issues/:id/actions_menu", to: "issues#actions_menu", as: :actions_menu
    get   "issues/:id/edit_form", to: "issues#edit_form", as: :edit_form

    # Issues summary
    get   "issues/:id/summary", to: "issues#summary", id: /\d+/,  as: :issue_summary

    # Issues partials
    get   "issues/:id/partials/body", to: "issues_partials#body", as: :issues_body_partial
    get   "issues/:id/partials/load_more", to: "issues_partials#load_more", as: :issues_load_more_partial
    get   "issues/:id/partials/transfer_form_possible_repositories", to: "issues_partials#transfer_form_possible_repositories", as: :issues_transfer_form_possible_repositories_partial
    get   "issues/:id/partials/transfer_form", to: "issues_partials#transfer_form", as: :issues_transfer_form_partial
    get   "issues/:id/partials/unread_timeline", to: "issues_partials#unread_timeline", as: :issues_unread_timeline_partial

    scope module: :issues do
      put     "issues/:id/assignees",     to: "assignees#update",         id: /\d+/, as: :assignees
      delete  "issues/:id/unassign_self", to: "assignees#unassign_self",  id: /\d+/, as: :unassign_self_from_issue

      post  "issues/:id/branch", to: "branch#create",  id: /\d+/, as: :create_branch_for_issue
      get  "issues/:id/branch/new", to: "branch#new",  id: /\d+/, as: :create_branch_for_issue_form
      get  "issues/:id/branch/target_repositories", to: "branch/target_repositories#index",  id: /\d+/, as: :create_branch_for_issue_target_repositories
      get  "issues/:id/branch/source_branch/new", to: "branch/source_branch#new",  id: /\d+/, as: :create_branch_for_issue_source_branch
    end

    put   "issues/prioritize",        to: "pinned_issues#prioritize", as: :prioritize_pinned_issue
    post  "issues/:id/pin",           to: "pinned_issues#create",  as: :pin_issue
    delete "issues/:id/unpin",        to: "pinned_issues#destroy", as: :unpin_issue
    match "issues/:id/show_partial",  to: "issues#show_partial",  id: /\d+/,  as: :show_partial_issue, via: [:get, :post]
    put   "issues/:id/lock",          to: "issues#lock",          id: /\d+/,  as: :lock_issue
    put   "issues/:id/unlock",        to: "issues#unlock",        id: /\d+/,  as: :unlock_issue
    post  "issues/:id/transfer",      to: "issue_transfers#create", id:  /\d+/, as: :transfer_issue
    put   "issues/:id/set_milestone", to: "issues#set_milestone", id: /\d+/,  as: :set_milestone_issue
    post "issues/:id/duplicate",      to: "issues#unmark_as_duplicate", id: /\d+/, as: :unmark_issue_as_duplicate
    post "issues/:id/dismiss_first_contribution_prompt", to: "issues#dismiss_first_contribution_prompt", id: /\d+/, as: :dismiss_issue_first_contribution_prompt
    post "issues/:id/dismiss_first_contribution_prompt_and_redirect", to: "issues#dismiss_first_contribution_prompt_and_redirect", id: /\d+/, as: :dismiss_issue_first_contribution_prompt_and_redirect
    get  "issues/:id/show_from_project", to: "issues#show_from_project", id: /\d+/, as: :show_issue_from_project
    put  "issues/:id/labels", to: "issues/labels#update", id: /\d+/, as: :set_labels_issue
    get  "issues/:id/hovercard", to: "hovercards/issues_and_pull_requests#show", id: /\d+/
    get  "issues/:id/title", to: "issues#show_title", id: /\d+/
    put  "issues/:id/convert",  to: "issues#convert_to_discussion", id: /\d+/, as: :convert_issue

    ##
    # Tracking block methods
    put "issues/:id/tracking_block", to: "tracking_block#update", as: :tracking_block
    get "issues/:id/tracking_block_menu/:uuid/:type", to: "tracking_block_menu#show", as: :tracking_block_menu
    get "issues/:id/tracking_block/:uuid/autocomplete", to: "tracking_block/autocomplete#show", as: :autocomplete_tracking_block

    ##
    # Issue template editor
    get "issues/templates/edit", to: "issue_templates#edit", as: :edit_issue_templates
    post "issues/templates/save", to: "issue_templates#create_many", as: :save_issue_templates
    post "issues/templates/preview", to: "issue_templates#preview", as: :preview_issue_template
    post "issues/templates/markdown_preview", to: "issue_templates#markdown_preview", as: :markdown_preview_issue_template

    ##
    # Issues clean URLs
    match "issues/created_by/*creator",   to: "issues#index",                      via: [:get, :post], as: :issues_created_by,  creator: APP_FILTER_REGEX
    match "issues/assigned/:assignee",    to: "issues#index",                      via: [:get, :post], as: :issues_assigned
    match "issues/mentioned/:mentioned",  to: "issues#index",                      via: [:get, :post], as: :issues_mentioned
    match "pulls/:login",                 to: "issues#index", pulls_only: true, via: [:get, :post], as: :user_pull_requests
    match "pulls/created_by/:creator",    to: "issues#index", pulls_only: true, via: [:get, :post], as: :pulls_created_by,   creator: APP_FILTER_REGEX
    match "pulls/assigned/:assignee",     to: "issues#index", pulls_only: true, via: [:get, :post], as: :pulls_assigned
    match "pulls/mentioned/:mentioned",   to: "issues#index", pulls_only: true, via: [:get, :post], as: :pulls_mentioned
    get   "pulls/review-requested/:review_requested",   to: "issues#index", pulls_only: true, as: :pulls_review_requested

    ##
    # Pull requests
    get   "pull", to: redirect("/%{user_id}/%{repository}/pulls")
    get   "pulls", to:  "issues#index", pulls_only: true, as: :pull_requests
    post  "pull/:id/ready_for_review", to: "pull_requests#ready_for_review", pulls_only: true, as: :pull_request_ready_for_review
    post  "pull/:id/convert_to_draft", to: "pull_requests#convert_to_draft", pulls_only: true, as: :pull_request_convert_to_draft
    post  "pull/:id/apply_suggestions", to: "pull_requests#apply_suggestions", as: :pull_request_apply_suggestions
    post  "pull/:id/run_workflows",     to: "pull_requests#run_action_required_workflows",   pulls_only: true, as: :pull_request_run_action_required_workflows

    ##
    # Labels
    get     "labels",             to: "labels#index",                          as: :labels
    post    "labels",             to: "labels#create"
    post    "labels/:id/convert_issues_to_discussions",
      to: "convert_labelled_issues_to_discussions#create", id: /\d+/,
      as: :convert_labelled_issues_to_discussions

    put     "labels/:id",         to: "labels#update",   id: /.+/
    delete  "labels/:id",         to: "labels#destroy",  id: /.+/
    get     "labels/preview/:name", to: "labels#preview", name: /.+/, as: :label_preview
    get     "labels/:label_name", to: "issues#index",    label_name: /.+/,  as: :label

    ##
    # Old school labels routes
    get    "issues/labels",     to: "labels#index"
    post   "issues/labels",     to: "labels#create"
    get    "issues/labels/:id", to: "labels#show",     id: /.+/
    put    "issues/labels/:id", to: "labels#update",   id: /.+/
    delete "issues/labels/:id", to: "labels#destroy",  id: /.+/

    ##
    # Catch-all for issues, same as "issues/created_by/:creator"
    get "issues/:creator",  to: "issues#index", creator: APP_FILTER_REGEX, format: false, defaults: { format: "html" }

    ##
    # Issue comments
    post   "issue_comments",                          to: "issue_comments#create", as: :issue_comments
    put    "issue_comments/:id",                      to: "issue_comments#update", as: :issue_comment
    delete "issue_comments/:id",                      to: "issue_comments#destroy"
    get    "issue_comments/:id/comment_actions_menu", to: "issue_comments#comment_actions_menu", as: :issue_comment_actions_menu
    get    "issue_comments/:id/edit_form",            to: "issue_comments#edit_form", as: :issue_comment_edit_form

    ##
    # Comment partials

    get "comments/:id/partials/block_from_comment_modal", to: "comment_partials#block_from_comment_modal", as: :block_from_comment_modal
    get "comments/:id/partials/timeline_issue_comment", to: "comment_partials#timeline_issue_comment", as: :timeline_issue_comment

    # Slash commands (Slash apps)
    resources :slash_apps, only: [:index], module: "slash_commands"
    patch "slash_apps/:command_id/:trigger", to: "slash_commands/slash_apps#update", as: :slash_app

    ##
    # User Lists
    resource :lists, controller: "repository_user_lists", only: [:show, :update], as: :repo_user_lists

    ##
    # Issue permalinks
    # XXX: Legacy - this will 301 to /:user_id/:repository/issues/:id in the controller
    get    "issues/issue/:id", to: "issues#show", legacy: true

    get "generate", to: "clone_template_repositories#new", as: :clone_template_repository

    # Dependency Graph
    if GitHub.dependency_graph_enabled? || (Rails.env.test? && GitHub.enterprise?)
      get "dependency-review/:base_sha/:head_sha/rich_diff", to: "dependency_review#rich_diff", as: :dependency_review_rich_diff, constraints: { base_sha: GIT_OID_REGEX, head_sha: GIT_OID_REGEX }
      get "/dependency-graph/package_hovercard", to: "hovercards/dependency_graph#show", as: :dependency_graph_package_hovercard
      get "/dependency-graph/sbom", to: "dependency_graph_sbom#show", as: :dependency_graph_sbom, defaults: { format: :json }
    end

    # RepositoryRulesBypassRequestsController
    get     "settings/rules/bypass_requests",            to: "repository_rules_bypass_requests#index",              as: :repository_rules_bypass_requests
    get     "settings/rules/bypass_requests/requesters",       to: "repository_rules_bypass_requests#bypass_request_requesters",  as: :repository_rules_bypass_request_requesters
    get     "settings/rules/bypass_requests/approvers",       to: "repository_rules_bypass_requests#bypass_request_approvers",  as: :repository_rules_bypass_request_approvers

    # SecretScanningBypassRequestsController
    get     "security/secret_scanning/bypass_requests",            to: "secret_scanning_bypass_requests#index",                     as: :secret_scanning_bypass_requests
    get     "security/secret_scanning/bypass_requests/requesters", to: "secret_scanning_bypass_requests#bypass_request_requesters", as: :secret_scanning_bypass_request_requesters
    get     "security/secret_scanning/bypass_requests/approvers",  to: "secret_scanning_bypass_requests#bypass_request_approvers",  as: :secret_scanning_bypass_request_approvers

    ##
    # EditRepositoriesController
    get    "settings",                             to: "edit_repositories#options",               as: :edit_repository
    put    "settings/update",                      to: "edit_repositories#update",                as: :update_repository
    put    "settings/update_archive_settings",     to: "edit_repositories#update_archive_settings", as: :update_repository_archive_settings
    put    "settings/update_push_settings",        to: "edit_repositories#update_push_settings",  as: :update_repository_push_settings
    put    "settings/update_merge_settings",       to: "edit_repositories#update_merge_settings", as: :update_repository_merge_settings
    put    "settings/update_default_branch",       to: "edit_repositories#update_default_branch", as: :update_repository_default_branch
    put    "settings/update_wiki_settings",        to: "edit_repositories#update_wiki_settings",  as: :update_repository_wiki_settings
    put    "settings/update_wiki_access",          to: "edit_repositories#update_wiki_access",    as: :update_repository_wiki_access
    put    "settings/update_dco_settings",         to: "edit_repositories#update_dco_settings",   as: :update_repository_dco_settings
    put    "settings/update_branch_protection",    to: "edit_repositories#update_branch_protection_settings", as: :update_repository_branch_protection_settings
    put    "settings/update_issue_settings",       to: "edit_repositories#update_issue_settings", as: :update_repository_issue_settings
    post   "settings/rename",                      to: "edit_repositories#rename",                as: :repo_rename
    post   "settings/transfer",                    to: "edit_repositories#transfer",              as: :repo_transfer
    get    "settings/transfer",              to: "edit_repositories#transfer_team_suggestions",        as: :repo_transfer_team_suggestions
    post   "settings/abort_transfer",              to: "edit_repositories#abort_transfer",        as: :repo_abort_transfer
    put    "settings/update_meta",                 to: "edit_repositories#update_meta",           as: :update_repo_meta
    put    "settings/update_topics",               to: "edit_repositories#update_topics",         as: :update_repo_topics
    put    "settings/update_member/:member_login", to: "edit_repositories#update_member",         as: :repository_update_member
    get    "settings/member_suggestions",          to: "edit_repositories#member_suggestions",    as: :repository_member_suggestions
    post   "settings/set_visibility",              to: "edit_repositories#set_visibility"
    post   "settings/detach",                      to: "edit_repositories#detach"
    put    "settings/change_anonymous_git_access", to: "edit_repositories#change_anonymous_git_access"
    delete "settings/remove_team",                 to: "edit_repositories#remove_team"
    delete "settings/remove_member",               to: "edit_repositories#remove_member"
    get    "settings/keys(/:id)",                  to: "edit_repositories#keys",                  as: :repository_keys, id: /\d+/
    get    "settings/keys/new",                    to: "edit_repositories#new_key",               as: :repository_new_key
    get    "rules",                                to: "repos/repository_ruleset#ruleset_index",          as: :view_repository_rulesets
    get    "rules/:id",                            to: "repos/repository_ruleset#ruleset_show",           as: :view_repository_ruleset
    get    "settings/rules",                       to: "edit_repositories#ruleset_index",              as: :repository_rulesets
    get    "settings/rules/:id/history/:history_id/compare(/:compare_history_id)", to: "edit_repositories#ruleset_history_comparison", as: :compare_rulesets
    get    "settings/rules/new",                   to: "edit_repositories#ruleset_new",           as: :new_repository_ruleset
    get    "settings/rules/:id/history",           to: "edit_repositories#ruleset_history_summary"
    get    "settings/rules/:id/history/:history_id/view", to: "edit_repositories#ruleset_history_view", as: :view_ruleset_history
    post   "settings/rules/validate_value/:type",  to: "edit_repositories#ruleset_validate_value",      as: :repository_ruleset_value_validation
    post   "settings/rules/validate_import",       to: "edit_repositories#ruleset_validate_import"
    get    "settings/rules/integration_suggestions",  to: "edit_repositories#ruleset_integration_suggestions"
    post   "settings/rules/deferred_target_counts", to: "edit_repositories#ruleset_deferred_target_counts"
    get    "settings/rules/status_check_suggestions", to: "edit_repositories#status_check_suggestions"
    get    "settings/rules/deployment_environment_suggestions", to: "edit_repositories#deployment_environment_suggestions"
    get    "settings/rules/merge_queue_merge_methods", to: "edit_repositories#merge_queue_merge_methods"
    get    "settings/rules/insights",              to: "edit_repositories#rule_insights",         as: :repository_rule_insights
    get    "settings/rules/insights/actors",       to: "edit_repositories#rule_insights_actors",  as: :repository_rule_insights_actors
    get    "settings/rules/:id/required_reviewer_suggestions",  to: "edit_repositories#ruleset_required_reviewer_suggestions"
    get    "settings/rules/:id/bypass_suggestions", to: "edit_repositories#ruleset_bypass_suggestions"
    get    "settings/rules/:id/export_ruleset/:history_id", to: "edit_repositories#export_ruleset"
    get    "settings/rules/:id/export_ruleset", to: "edit_repositories#export_ruleset"
    get    "settings/rules/:id",                   to: "edit_repositories#ruleset_show",               as: :repository_ruleset
    post   "settings/rules/:id",                   to: "edit_repositories#ruleset_update",           as: :set_repository_ruleset
    delete "settings/rules/:id",                   to: "edit_repositories#ruleset_destroy",        as: :delete_repository_ruleset
    delete "settings/delete",                      to: "edit_repositories#delete"
    post   "settings/request_bypass/:action_type", to: "edit_repositories#request_bypass",      as: :repository_request_bypass
    post   "settings/archive",                     to: "edit_repositories#archive"
    post   "settings/unarchive",                   to: "edit_repositories#unarchive"
    get    "settings/access",                      to: "edit_repositories#access",                as: :repository_access_management
    post   "settings/add_team",                    to: "edit_repositories#add_team"
    post   "settings/add_member",                  to: "edit_repositories#add_member"
    get    "settings/branches",                    to: "edit_repositories#branches",              as: :edit_repository_branches
    get    "settings/interaction_limits",          to: "edit_repositories/interaction_limits#show",    as: :repository_interaction_limits
    put    "settings/interaction_limits",          to: "edit_repositories/interaction_limits#update",  as: :set_repository_interaction_limit
    get    "settings/code_review_limits",          to: "edit_repositories/code_review_limits#show", as: :repository_code_review_limits
    put    "settings/code_review_limits",          to: "edit_repositories/code_review_limits#update", as: :set_repository_code_review_limits
    put    "settings/projects",                    to: "edit_repositories#toggle_projects",       as: :toggle_repository_projects
    get    "settings/tag_protection",              to: "edit_repositories/tag_protection#index",       as: :edit_repository_tag_protection
    get    "settings/tag_protection/new",          to: "edit_repositories/tag_protection#new",       as: :new_repository_tag_protection
    post    "settings/tag_protection/check_pattern", to: "edit_repositories/tag_protection#check_pattern",       as: :check_repository_tag_protection
    post   "settings/tag_protection",              to: "edit_repositories/tag_protection#create",       as: :create_repository_tag_protection
    post   "settings/tag_protection/import",       to: "edit_repositories/tag_protection#import",       as: :import_repository_tag_protection
    delete "settings/tag_protection/:tag_protection_id", to: "edit_repositories/tag_protection#delete",       as: :delete_repository_tag_protection
    put    "settings/discussion_activation",      to: "edit_repositories/discussion_activation#update", as: :repository_discussion_activation
    get    "settings/dependabot_rules",         to: "repos/security_and_analysis/dependabot_rules#index",          as: :dependabot_rules
    get    "settings/dependabot_rules/new",     to: "repos/security_and_analysis/dependabot_rules#new",            as: :new_dependabot_rule
    post   "settings/dependabot_rules",         to: "repos/security_and_analysis/dependabot_rules#create",         as: :create_dependabot_rule
    get    "settings/dependabot_rules/edit/:rule_id",  to: "repos/security_and_analysis/dependabot_rules#edit",    as: :edit_dependabot_rule
    get    "settings/dependabot_rules/view/:rule_id",  to: "repos/security_and_analysis/dependabot_rules#show",    as: :show_dependabot_rule
    put    "settings/dependabot_rules/:rule_id",         to: "repos/security_and_analysis/dependabot_rules#update",  as: :update_dependabot_rule
    get    "settings/dependabot_rules/edit_parent/:id", to: "repos/security_and_analysis/dependabot_rules#edit_parent_rule", as: :edit_parent_dependabot_rule
    put    "settings/dependabot_rules/update_parent/:id", to: "repos/security_and_analysis/dependabot_rules#update_parent_rule",  as: :update_parent_dependabot_rule
    delete "settings/delete_dependabot_rule/:rule_id", to: "repos/security_and_analysis/dependabot_rules#destroy", as: :delete_dependabot_rule

    delete "settings/pages/unpublish",               to: "edit_repositories#unpublish_page",      as: :unpublish_page

    post    "members",                             to: "edit_repositories/manage_access#add_member",               as: :add_repository_member
    put     "settings/update_members",             to: "edit_repositories/manage_access#update_members",           as: :update_repository_members
    delete  "settings/remove_members",             to: "edit_repositories/manage_access#remove_members"
    get     "settings/toolbar_actions",            to: "edit_repositories/manage_access#members_toolbar_actions",  as: :members_toolbar_actions
    get     "settings/role_details",               to: "edit_repositories/manage_access#role_details",             as: :settings_role_details

    get    "invite_member",                        to: "repos/invitations#new"

    get "settings/og-template",                      to: "repository_open_graph_images#template",
      as: :repository_open_graph_template
    delete "settings/open-graph-image",              to: "repository_open_graph_images#destroy",
      as: :repository_open_graph_image

    scope path: "settings", module: :settings do
      resources :key_links do
        post "check", on: :collection
      end
    end

    scope path: "settings" do
      get  "branch_protection_rules/integration_suggestions",   to: "branch_protection_rules#integration_suggestions",   as: :branch_protection_rules_integration_suggestions

      resources :branch_protection_rules, except: [:index]

      resources :copilot_code_guidelines, controller: "edit_repositories/copilot_code_guidelines", only: [:new, :edit, :create, :update, :destroy] do
        resource :enablement, controller: "edit_repositories/copilot_code_guidelines/enablements", only: [:create]
        member do
          resources :occurrences, controller: "edit_repositories/copilot_code_guidelines_occurrences", only: [:index]
        end
      end
      scope path: "copilot_code_guidelines", as: :copilot_code_guidelines do
        resource :playground_runs, controller: "edit_repositories/copilot_code_guidelines/playground_runs", only: [:create]
        resource :sample_code_generation, controller: "edit_repositories/copilot_code_guidelines/sample_code_generations", only: [:create]
      end
    end

    get "transfer", to: "repos/transfer#show", as: :transfer_repo

    ##
    # RepositoryAnnouncementController
    get    "settings/announcement",               to: "edit_repositories/repository_announcement#announcement",       as: :edit_repository_announcement
    put    "settings/preview_announcement", to:    "edit_repositories/repository_announcement#preview_announcement",      as: :repository_announcement_preview
    patch  "settings/announcement", to:            "edit_repositories/repository_announcement#set_announcement",          as: :repository_set_announcement
    delete "settings/announcement", to:            "edit_repositories/repository_announcement#destroy",      as: :repository_destroy_announcement

    ##
    # RepositoryPagesSettingsController
    get   "settings/pages",         to: "repository_pages_settings#index",    as: :repository_pages_settings

    ##
    # RepositoryPropertiesController
    get  "custom-properties",                  to: "repository_custom_properties#overview",    as: :repository_custom_properties_overview
    get  "settings/custom-properties",         to: "repository_custom_properties#settings",    as: :repository_custom_properties_settings
    post "settings/custom-properties/values",  to: "repository_custom_properties#update",      as: :repository_custom_properties_update, format: :json

    ##
    # RepositoryNotificationSettingsController
    get    "settings/notifications",               to: "repository_notification_settings#index",   as: :repository_notification_settings
    get    "settings/notifications/edit",          to: "repository_notification_settings#edit",    as: :edit_repository_notification_settings
    put    "settings/notifications",               to: "repository_notification_settings#update",  as: :update_repository_notification_settings
    delete "settings/notifications",               to: "repository_notification_settings#destroy", as: :destroy_repository_notification_settings

    ##
    # Repos::SecurityAndAnalysis::SettingsController
    get "settings/security_analysis",                                         to: "repos/security_and_analysis/settings#security_analysis",                         as: :repository_security_and_analysis
    put "settings/update_ghas_settings",                                      to: "repos/security_and_analysis/settings#update_ghas_settings",                      as: :update_repository_ghas_settings
    put "settings/update_security_products_settings",                         to: "repos/security_and_analysis/settings#update_security_products_settings",         as: :update_security_products_settings
    get "settings/security_analysis/automatic_dependency_submission_options", to: "repos/security_and_analysis/settings#automatic_dependency_submission_options",   as: :repository_security_and_analysis_ads_opts

    ##
    # Repos::SecurityAndAnalysis::CodeScanning::SeveritySettingsController
    put "settings/code_scanning/severity", to: "repos/security_and_analysis/code_scanning/severity_settings#update", as: :repository_code_scanning_severity

    ##
    # Repos::SecurityAndAnalysis::CodeScanning::AutofixSettingsController
    match "settings/code_scanning/autofix/:policy", to: "repos/security_and_analysis/code_scanning/autofix_settings#update", via: [:post, :put], as: :repository_code_scanning_autofix_settings

    ##
    # Repos::SecurityAndAnalysis::CodeScanning::DelegatedAlertDismissalSettingsController
    match "settings/code_scanning/protected_alert_dismissal", to: "repos/security_and_analysis/code_scanning/delegated_alert_dismissal_settings#update", via: [:post, :put], as: :repository_code_scanning_delegated_alert_dismissal_settings

    ##
    # Repos::SecurityAndAnalysis::CodeScanning::AlertDismissalController
    put "security/code-scanning/alert-dismissal", to: "repos/security_and_analysis/code_scanning/alert_dismissal#create", as: :repository_code_scanning_dismissal_request_create
    put "security/code-scanning/alert-dismissal/approve", to: "repos/security_and_analysis/code_scanning/alert_dismissal#approve_request", as: :repository_code_scanning_dismissal_request_approve
    put "security/code-scanning/alert-dismissal/reject", to: "repos/security_and_analysis/code_scanning/alert_dismissal#reject_request", as: :repository_code_scanning_dismissal_request_reject

    ##
    # Repos::SecurityAndAnalysis::CodeScanning::AutoCodeqlSettingsController
    get "settings/code-scanning/default-setup",  to: "repos/security_and_analysis/code_scanning/auto_codeql_settings#edit",  as: :edit_repository_auto_codeql
    post "settings/code_scanning/auto_codeql",  to: "repos/security_and_analysis/code_scanning/auto_codeql_settings#create",  as: :create_repository_auto_codeql
    post "settings/code_scanning/auto_codeql_modal",  to: "repos/security_and_analysis/code_scanning/auto_codeql_settings#create_modal",  as: :create_repository_auto_codeql_modal
    post "settings/code_scanning/auto_codeql/switch", to: "repos/security_and_analysis/code_scanning/auto_codeql_settings#switch", as: :switch_codeql_setup
    put "settings/code_scanning/auto_codeql",  to: "repos/security_and_analysis/code_scanning/auto_codeql_settings#update",  as: :update_repository_auto_codeql
    delete "settings/code_scanning/auto_codeql",  to: "repos/security_and_analysis/code_scanning/auto_codeql_settings#destroy",  as: :destroy_repository_auto_codeql

    ##
    # Repos::SecurityAndAnalysis::CodeScanning::StatusController
    get "settings/code_scanning/status", to: "repos/security_and_analysis/code_scanning/status#index", as: :repository_code_scanning_status
    delete "settings/code_scanning/dismiss_auto_codeql_error_notice", to: "repos/security_and_analysis/code_scanning/status#dismiss_auto_codeql_error_notice", as: :dismiss_auto_codeql_error_notice

    ##
    # Repos::SecurityAndAnalysis::CodeScanning::AutoCodeqlMessagesController
    get "settings/code_scanning/auto_codeql_messages", to: "repos/security_and_analysis/code_scanning/auto_codeql_messages#index", as: :repository_code_scanning_auto_codeql_messages


    ##
    # SecretsController
    constraints app_name: /actions|dependabot|codespaces/ do
      get    "settings/secrets/:app_name",                     to: "secrets#secrets",               as: :repository_secrets
      delete "settings/secrets/:app_name/:key",                to: "secrets#remove_secret",         as: :repository_remove_secret
      get    "settings/secrets/:app_name/new",                 to: "secrets#new_secret",            as: :repository_new_secret
      post   "settings/secrets/:app_name/new",                 to: "secrets#add_secret",            as: :repository_add_secret
      get    "settings/secrets/:app_name/:secret_name",        to: "secrets#edit",                  as: :repository_edit_secret
      put    "settings/secrets/:app_name/:secret_name",        to: "secrets#update",                as: :repository_update_secret
    end

    # Redirects to support previous Actions secrets routes
    get    "settings/secrets",                     to: redirect("/%{user_id}/%{repository}/settings/secrets/actions")
    get    "settings/secrets/new",                 to: redirect("/%{user_id}/%{repository}/settings/secrets/actions/new")
    get    "settings/secrets/:secret_name",        to: redirect("/%{user_id}/%{repository}/settings/secrets/actions/%{secret_name}")

    ##
    # RepositoryInvitationsController
    post   "uninvite_member",             to: "repository_invitations#destroy"

    ##
    # EditRepositoriesController redirects
    get "settings/delete", to: redirect("/%{user_id}/%{repository}/settings")
    get "admin",           to: redirect("/%{user_id}/%{repository}/settings")
    get "admin/:path",     to: redirect("/%{user_id}/%{repository}/settings/%{path}")
    get "edit",            to: redirect("/%{user_id}/%{repository}/settings")
    get "edit/:path",      to: redirect("/%{user_id}/%{repository}/settings/%{path}")
    get "settings/fine_grained", to: redirect("/%{user_id}/%{repository}/settings")
    # nb: this endpoint is for backwards compability while migrating to edit_repositories#access instead
    get "settings/collaboration", to: redirect("/%{user_id}/%{repository}/settings/access")

    ##
    # EditRepositoriesController environment specific routes
    if GitHub.custom_tabs_enabled?
      get    "settings/tabs",       to: "edit_repositories#tabs",       as: :repository_tabs
      post   "settings/add_tab",    to: "edit_repositories#add_tab"
      delete "settings/remove_tab", to: "edit_repositories#remove_tab"
    end

    ##
    # PagesController
    get  "settings/pages/status",             to: "pages#status",              as: :pages_status
    get  "settings/pages/certificate_status", to: "pages#certificate_status", as: :pages_certificate_status
    get  "settings/pages/domain_status",      to: "pages#domain_status",      as: :pages_domain_status
    put  "settings/pages/request_https_certificate",  to: "pages#request_https_certificate",  as: :pages_request_https_certificate
    put  "settings/pages/https_status",       to: "pages#https_status",       as: :pages_https_status
    put  "settings/pages/visibility",         to: "pages#visibility",         as: :pages_visibility
    put  "settings/pages/cname",              to: "pages#cname",              as: :pages_cname
    put  "settings/pages/custom_subdomain",   to: "pages#custom_subdomain",   as: :pages_custom_subdomain
    put  "settings/pages/build_type",         to: "pages#build_type",         as: :pages_build_type
    put  "settings/pages/source",             to: "pages#source",             as: :pages_source
    put  "settings/pages/https_redirect",     to: "pages#https_redirect",     as: :pages_https_redirect
    delete "settings/pages/deployment",       to: "pages#delete_deployment",  as: :pages_delete_deployment

    ##
    # Delegated Bypass/Exemption Requests
    # RepositoryRulesBypassRequestsController
    get "exemptions/new/:encoded", to: "repository_rules_bypass_requests#new", as: :ruleset_new_bypass_request
    post "exemptions/new/:encoded", to: "repository_rules_bypass_requests#create"
    put "exemptions/:number", to: "repository_rules_bypass_requests#update"
    get "exemptions/:number", to: "repository_rules_bypass_requests#show", as: :ruleset_bypass_request
    get "exemptions/:number/approvers", to: "repository_rules_bypass_requests#approvers"

    ##
    # Secret Scanning Exemption Requests
    # SecretScanningBypassRequestsController
    get "secret_scanning/exemptions/new/:encoded", to: "secret_scanning_bypass_requests#new", as: :secret_scanning_new_bypass_request
    post "secret_scanning/exemptions/new/:encoded", to: "secret_scanning_bypass_requests#create"
    put "secret_scanning/exemptions/:number", to: "secret_scanning_bypass_requests#update"
    get "secret_scanning/exemptions/:number", to: "secret_scanning_bypass_requests#show", as: :secret_scanning_bypass_request

    ##
    # Secret Scanning Alert Closure Requests
    # SecretScanningClosureRequestsController
    put "secret_scanning/closure_requests/:number", to: "repos/secret_scanning/secret_scanning_closure_requests#update"


    ##
    # BranchesController
    get    "branches",                       to: "branches#index",         as: :branches
    post   "branches",                       to: "branches#create",        as: :create_branch
    delete "branches/:name",                 to: "branches#destroy",       as: :destroy_branch,             name: /.+/
    put    "branches/:name",                 to: "branches#update",        as: :branch,                     name: /.+/
    get    "branches/yours",                 to: "branches#yours"
    get    "branches/active",                to: "branches#active"
    get    "branches/stale",                 to: "branches#stale"
    get    "branches/all",                   to: "branches#all"
    post   "branches/deferred_metadata",     to: "branches#deferred_metadata", as: :deferred_branch_metadata
    get    "branches/history(/:name)",       to: "branches#history",       as: :repository_branch_history,  name: BRANCH_REGEX
    post   "branches/recover",               to: "branches#recover",       as: :recover_branch
    get    "branches/pre_mergeable/:range",  to: "branches#pre_mergeable", as: :pre_mergeable,              range: /.+/
    post   "ref_check",                      to: "branches#ref_check",     as: :ref_check
    post   "branches/:name/rename_ref_check", to: "branches#rename_ref_check", as: :rename_ref_check,  name: /.+/
    post   "branches/fetch_and_merge/:name",  to: "branches#fetch_and_merge",  as: :fetch_and_merge,  name: /.+/
    get    "branches/rename_form/:name",     to: "branches#rename_form",   as: :branch_rename_form, name: /.+/
    get    "branches/authorization_suggestions", to: "branch_authorization#suggestions", as: :branch_authorization_suggestions
    get    "branches/authorized_actor",      to: "branch_authorization#authorized_actor", as: :branch_authorized_actor
    get    "branches/required_status_context", to: "branch_required_status_contexts#show", as: :branch_required_status_context
    get    "branches/required_status_context_suggestions", to: "branch_required_status_contexts#suggestions", as: :branch_required_status_context_suggestions
    get    "branches/delete_branch_dialog/:name",            to: "branches#delete_branch_dialog",    as: :branch_delete_branch_dialog, name: /.+/
    post   "branches/check_tag_name_exists",            to: "branches#check_tag_name_exists",    as: :check_tag_name_exists
    get    "branch/target_repositories",     to: "branches#target_repositories", as: :create_branch_target_repositories
    get    "branch/source_branch",           to: "branches#source_branch", as: :create_branch_source_branch
    # Show a nice feature retired message rather than a 404 to users who visit
    # the old base-switching branches page route:
    get    "branches/*name", to: "feature_gone#index"

    ##
    ## AccessToAlertsController
    get    "access_to_alerts/suggestions",            to: "repos/security_and_analysis/access_to_alerts#suggestions",         as: :access_to_alerts_suggestions
    get    "access_to_alerts/authorized_actor",       to: "repos/security_and_analysis/access_to_alerts#authorized_actor",    as: :access_to_alerts_actor
    put    "settings/alerts",                         to: "repos/security_and_analysis/access_to_alerts#update_alerts",       as: :edit_repository_alert

    ##
    # RepositoryCodespacesController
    get    "codespaces",                     to: "codespaces/repository_codespaces#index",           as: :repository_codespaces
    get    "codespaces/allow_permissions",   to: "codespaces/repository_codespaces#allow_permissions", as: :repository_codespaces_allow_permissions
    get    "codespaces/code_menu_contents",  to: "codespaces/repository_codespaces#code_menu_contents", as: :repository_codespaces_code_menu_contents
    post   "codespaces/add_consented_permissions", to: "codespaces/repository_codespaces#add_consented_permissions", as: :repository_codespaces_add_consented_permissions
    get    "codespaces/configure/dev_container",          to: "codespaces/dev_containers#create",    as: :repository_codespaces_configure_dev_container

    ##
    # RepositoryCodespacesSettingsController
    get    "settings/codespaces",            to: "codespaces/repository_settings#index",        as: :codespaces_repository_settings
    # PrebuildConfigurationsController

    resources :codespaces_prebuild_configurations, path: "settings/codespaces/prebuild_configurations", controller: "codespaces/prebuild_configurations", only: [:new, :create, :edit, :update, :destroy] do
      collection do
        get "suggested_notifiers", to: "codespaces/prebuild_configurations#suggested_notifiers"
        post "update_notifiers", to: "codespaces/prebuild_configurations#update_notifiers"
        post "update_config_info", to: "codespaces/prebuild_configurations#update_config_info"
        post "add_consented_permissions", to: "codespaces/prebuild_configurations#add_consented_permissions"
      end

      member do
        post "run_workflow", to: "codespaces/prebuild_configurations#run_workflow"
        get "latest_run_status", to: "codespaces/prebuild_configurations#latest_run_status"
        post "toggle_state", to: "codespaces/prebuild_configurations#toggle_state"
      end
    end

    ##
    # Checks
    get  "commit/:ref/checks",                      to: "checks#index",                         as: :checks
    get  "commit/:ref/checks/:id",                  to: "checks#show",                          as: :checks_summary
    get  "commit/:ref/checks/:id/logs",             to: "checks#check_logs",                    as: :check_run_logs
    get  "commit/:ref/checks/:id/live_logs",        to: "checks#live_logs",                     as: :check_run_live_logs
    get  "commit/:ref/checks/:id/logs/:step",       to: "checks#step_logs",                     as: :check_step_logs, step: /\d+/
    get  "commit/:ref/checks/:id/annotations",      to: "checks#annotations",                   as: :checks_annotations
    get  "commit/:ref/rollup",                      to: "checks_statuses#rollup",               as: :checks_statuses_rollup
    get  "commit/:ref/checks_state_summary",        to: "checks#checks_state_summary",          as: :checks_state_summary
    get  "commit/:ref/status-details",              to: "checks_statuses#details",              as: :checks_statuses_details
    get  "commits/checks-statuses-rollups",         to: "checks_statuses#rollups",              as: :checks_statuses_batch_rollup
    get  "runs/:id",                                to: "check_runs#show",                      as: :check_run
    get  "runs/:id/checks_wait",                    to: "check_runs#show_checks_wait_partial",  as: :check_run_show_checks_wait_partial
    get  "runs/:id/header",                         to: "check_runs#show_header_partial",       as: :check_run_show_header_partial
    get  "runs/:id/toolbar",                        to: "check_runs#show_toolbar_partial",      as: :check_run_show_toolbar_partial
    put  "runs/:id/rerequest",                      to: "check_runs#rerequest",                 as: :rerequest_check_run
    put  "runs/:id/request_action",                 to: "check_runs#request_action",            as: :request_action_check_run
    put  "suites/:id/rerequest",                    to: "check_suites#rerequest",               as: :rerequest_check_suite
    get  "suites/:id/show_partial",                 to: "check_suites#show_partial",            as: :check_suite_show_partial
    put  "suites/:id/cancel",                       to: "check_suites#cancel",                  as: :cancel_check_suite
    get  "suites/:id/artifacts/:artifact_id",       to: "check_suites#download_artifact",       as: :download_artifact
    delete  "suites/:id/artifacts/:artifact_id",    to: "check_suites#delete_artifact",         as: :delete_artifact
    get  "suites/:id/logs",                         to: "check_suites#download_logs",           as: :check_suite_logs

    ##
    # FileCollaboratorPrompt
    get "/collaborator_prompt(/*path)", to: "collaborator_prompt#show", as: :collaborator_prompt

    ##
    # Commit
    get    "commit/:name/hovercard",            to: "hovercards/commits#show"
    get    "commit/:name/show_partial",         to: "commit#show_partial",         as: :show_partial_commit
    get    "commit/:name/context_lines",        to: "commit#context_lines",        as: :context_lines, format: "json"
    get    "commit/:name/rich_diff(/*path)",      to: "commit#rich_diff",            as: :commit_rich_diff, format: false, defaults: { format: :json }
    get    "commit/:name/discussion_comments",  to: "commit#discussion_comments", as: :commit_discussion_comments, format: "json"
    get    "commit/:name/inline_comments",      to: "commit#inline_comments",      as: :commit_inline_comments, format: "json"
    get    "commit/:name/deferred_comment_data", to: "commit#deferred_comment_data", as: :commit_deferred_comment_data, format: "json"
    get    "commit/:name/deferred_commit_data",  to: "commit#deferred_commit_data", as: :commit_deferred_commit_data, format: "json"

    get    "commit/:name(/*path)",              to: "commit#show",                 as: :commit, format: false
    get    "commit/:name.:format",              to: "commit#show"
    get    "check_commit_quorum/:name",         to: "commit#check_commit_quorum",  as: :check_commit_quorum
    get    "spoofed_commit_check/:name",        to: "commit#spoofed_commit_check", as: :spoofed_commit_check
    get    "branch_commits/:name",              to: "commit#branch_commits",       as: :branch_commits
    get    "commit",                            to: "commit#show"
    put    "commit/:name/lock",                 to: "commit#lock",                 as: :lock_commit
    put    "commit/:name/unlock",               to: "commit#unlock",               as: :unlock_commit

    ##
    # CommitsController
    get   "commits/:name/commits_list_item", to: "commits#commits_list_item", as: :commits_list_item, constraints: { name: /.+/ }, format: false
    get   "commits/deferred_commit_data(/*name)", to: "commits#deferred_commit_data", as: :deferred_commit_data, constraints: { name: /.+/ }
    get   "commits/deferred_commit_contributors", to: "commits#deferred_commit_contributors", as: :deferred_commit_contributors
    get   "commits/check_for_rename_commits", to: "commits#check_for_rename_commits", as: :nil
    post  "commits/check_for_rename_commits", to: "commits#check_for_rename_commits", as: :check_for_rename_commits
    get   "commits(/*name).:format", to: "commits#show", as: :commits_feed, constraints: { name: /.+/, format: "atom" }, defaults: { format: "atom" }
    get   "commits(/*name)",         to: "commits#show",                       constraints: { name: /.+/ }, format: false, defaults: { format: "html" }

    ##
    # Commit Comments
    get    "commit_comment/:id",    to: "commit_comments#show",    id: /\d+/, defaults: { raw: true }, as: :commit_comment
    delete "commit_comment(/:id)",    to: "commit_comments#destroy", id: /\d+/, as: :destroy_commit_comment
    put    "commit_comment(/:id)",    to: "commit_comments#update",  id: /\d+/, as: :update_commit_comment
    get    "commit_comment/:id/comment_actions_menu", to: "commit_comments#comment_actions_menu", as: :commit_comment_actions_menu
    get    "commit_comment/:id/edit_form",            to: "commit_comments#edit_form",       as: :commit_comment_edit_form
    put    "commit_comment/:id/minimize",             to: "commit_comments#minimize",        as: :commit_comment_minimize
    put    "commit_comment/:id/unminimize",           to: "commit_comments#unminimize",      as: :commit_comment_unminimize
    post   "commit_comment/create", to: "commit_comments#create",                as: :create_commit_comment

    ##
    # Activity
    get "activity", to: "activity#index", as: :activity_index
    get "activity/actors", to: "activity#actors", as: :activity_actors

    ## Community
    #
    get  "community",                             to: "community#index",                as: :community
    get  "community/code-of-conduct/new",         to: "community#code_of_conduct_tool", as: :code_of_conduct_tool
    post "community/code-of-conduct",             to: "community#code_of_conduct",      as: :add_code_of_conduct
    get  "community/license/new",                 to: "community#license_tool",         as: :license_tool
    post "community/licenset",                    to: "community#license",              as: :add_license
    put  "community/minimize-comment",            to: "community#minimize_comment",        as: :minimize_comment
    put  "community/unminimize-comment",          to: "community#unminimize_comment",      as: :unminimize_comment

    ##
    # Compare
    get    "compare/repository-list", to: "compare#repository_list", as: :compare_repository_list
    get    "compare/branch-list", to: "compare#branch_list", as: :compare_branch_list
    get    "compare/tag-list",    to: "compare#tag_list",    as: :compare_tag_list
    get    "compare/commit-list", to: "compare#commit_list", as: :compare_commit_list
    get    "compare/file-list", to: "compare#file_list", as: :compare_file_list
    get    "compare/pr-templates",    to: "compare#pr_templates", as: :compare_pr_templates
    match  "compare/:range", to: "compare#show",  as: :compare,        via: [:get, :post], constraints: { range: /.+/ }, format: false, defaults: { format: :html }
    match  "compare",        to: "compare#new",   as: :compare_start,  via: [:get, :post]

    ##
    # Diffs
    get "diffs/:entry",            to: "diffs#show",  as: :diff, constraints: { entry: /\d+/ }
    get "diffs/:entry/diff-lines", to: "diffs#diff_lines", as: :diff_lines, constraints: { entry: /\d+/ }
    get "diffs",                   to: "diffs#index", as: :diffs

    get  "unchanged_files_with_annotations",      to: "diffs#unchanged_files_with_annotations",   as: :unchanged_files_with_annotations

    ##
    # Forking
    get    "fork",  to: "tree#fork_select",  as: :fork_select
    post   "fork",  to: "tree#fork",         as: :fork_repository

    namespace :forks do
      get "/", to: "forks#index"
      post "/default-options", to: "default_options#update", as: :default_options
    end

    ##
    # Graphs
    get    "graphs",                        to: "graphs#index",                   as: :repo_graphs
    get    "graphs/commit-activity",        to: "graphs#commit_activity",         as: :commit_activity
    get    "graphs/commit-activity-data",   to: "graphs#commit_activity_data",    as: :commit_activity_data
    get    "graphs/clone-activity-data",    to: "graphs#clone_activity_data",     as: :clone_activity_data
    get    "graphs/code-frequency",         to: "repos/insights/code_frequency#index", as: :code_frequency
    get    "graphs/code-frequency-data",    to: "repos/insights/code_frequency#data", as: :code_frequency_data
    get    "graphs/languages",              to: "graphs#languages",               as: :repository_languages
    get    "graphs/punch-card",             to: "graphs#punch_card",              as: :punch_card
    get    "graphs/punch-card-data",        to: "graphs#punch_card_data",         as: :punch_card_data

    get    "graphs/traffic",                to: "graphs#traffic",                 as: :traffic
    get    "graphs/traffic-data",           to: "graphs#traffic_data",            as: :traffic_data
    get    "graphs/contributors",           to: "repos/insights/contributors#index", as: :contributors_graph
    get    "graphs/contributors-data",      to: "repos/insights/contributors#data", as: :contributors_graph_data
    get    "graphs/clones",                 to: "graphs#clones",                  as: :clones
    get    "graphs/clones-data",            to: "graphs#clones_data",             as: :clones_next_data
    get    "graphs/participation",          to: "repository_participation#show",  as: :participation

    ##
    # Community Insights
    get "graphs/community",                           to: "graphs#community",                           as: :community_graph
    get "graphs/contributions-data",                  to: "graphs#contributions_data",                  as: :contributions_data
    get "graphs/discussions-daily-contributors-data", to: "graphs#discussions_daily_contributors_data", as: :discussions_daily_contributors_data
    get "graphs/discussions-new-contributors-data",   to: "graphs#discussions_new_contributors_data",   as: :discussions_new_contributors_data
    get "graphs/discussions-page-views-data",         to: "graphs#discussions_page_views_data",         as: :discussions_page_views_data

    ##
    # Hooks
    get    "settings/hooks",                to: "repository_hooks#index",          as: :repository_hooks
    post   "settings/hooks",                to: "repository_hooks#create"
    get    "settings/hooks/new",            to: "repository_hooks#new",            as: :new_repository_hook
    get    "settings/hooks/:id",            to: "repository_hooks#show",           as: :repository_hook
    put    "settings/hooks/:id",            to: "repository_hooks#update"
    delete "settings/hooks/:id",            to: "repository_hooks#destroy"

    constraints(guid: WEBHOOK_GUID_REGEX, id: WEBHOOK_REGEX, hook_id: /\d+/) do
      get  "settings/hooks/:hook_id/deliveries",                     to: "hook_deliveries#index",     as: :repository_hook_deliveries
      get  "settings/hooks/:hook_id/deliveries/:id",                 to: "hook_deliveries#show",      as: :repository_hook_delivery
      get  "settings/hooks/:hook_id/deliveries/:id/payload.:format", to: "hook_deliveries#payload",   as: :repository_hook_delivery_payload, format: "json"
      get  "settings/hooks/:hook_id/redeliveries",                     to: "hook_deliveries#redeliveries",     as: :repository_hook_redeliveries
      post "settings/hooks/:hook_id/deliveries/:guid/redeliver",       to: "hook_deliveries#redeliver", as: :repository_redeliver_hook_delivery
    end

    # GitHub Apps installed on a repository
    scope "settings", controller: :repository_installations do
      resources :repository_installations, path: "installations", param: :installation_id, only: [:index] do
        member do
          get :action, to: "repository_installations/actions#show"
        end
      end
    end

    if GitHub.enterprise?
      post   "settings/hooks/:id/update_pre_receive",        to: "repository_hooks#update_pre_receive",      as: :update_repository_pre_receive
    end

    ##
    # Network
    get    "network",            to: "network#show",       as: :network
    get    "network/meta",       to: "network#meta",       as: :network_meta
    get    "network/chunk",      to: "network#chunk",      as: :network_chunk
    get    "network/members",    to: "network#members",    as: :network_members

    if GitHub.dependency_graph_enabled?
      get    "network/dependents", to: "network#dependents", as: :network_dependents
      get    "network/dependencies", to: "network#dependencies", as: :network_dependencies
      get    "network/updates", to: "network/dependabot#index", as: :network_dependabot
      post   "network/updates", to: "network/dependabot#create", as: :create_network_dependabot_run
      get    "network/updates/:update_job_id", to: "network/dependabot#show", as: :network_dependabot_show
      get    "network/updates/:update_config_id/jobs", to: "network/dependabot/jobs#index", as: :network_dependabot_jobs_index
      put    "network/updates/enable", to: "network/dependabot#enable", as: :network_enable_dependabot
      post   "network/updates/access_recommendations/apply", to: "network/dependabot/access_recommendations#apply", as: :network_apply_dependabot_repository_access_recommendations
      post   "network/dependencies/vulnerabilities/disable_updates", to: "repository_vulnerability_updates#disable", as: :disable_vulnerability_updates
    end

    # Security Campaigns Controller
    get "security/campaigns/:number", to: "repos/security_campaigns/repositories#show", as: :repository_security_campaign
    post "security/campaigns/:number/branches", to: "repos/security_campaigns/alert_branches#create", as: :create_security_campaign_alert_branch
    get "security/campaigns/:number/alerts", to: "repos/security_campaigns/alerts#index", as: :repository_security_campaign_alerts
    post "security/campaigns/:number/alerts", to: "repos/security_campaigns/alerts#close", as: :close_security_campaign_alerts
    post "security/campaigns/:number/assign-to-copilot", to: "repos/security_campaigns/alerts#assign_to_copilot", as: :security_campaign_alerts_assign_to_copilot

    # Code Quality
    get "security/quality", to: "repos/code_quality/repositories#index", as: :repository_code_quality
    get "security/quality/rules", to: "repos/code_quality/rules#index", as: :repository_code_quality_rules
    get "security/quality/rules/:rule_id", to: "repos/code_quality/rules#show", as: :repository_code_quality_rule
    get "security/quality/rules/:rule_id/files", to: "repos/code_quality/rule_files#index", as: :repository_code_quality_rule_files
    get "security/quality/rules/:rule_id/findings", to: "repos/code_quality/rule_findings#index", as: :repository_code_quality_rule_findings

    get  "security/dependabot", to: "repos/dependabot_alerts#index", as: :repository_alerts
    put  "security/dependabot/:number/dismiss", to: "repos/dependabot_alerts#dismiss_one", as: :dismiss_repository_alert
    put  "security/dependabot/:number/reopen", to: "repos/dependabot_alerts#reopen", as: :reopen_repository_alert
    put  "security/dependabot/reopen-many", to: "repos/dependabot_alerts#reopen_many", as: :reopen_many_repository_alert
    put  "security/dependabot/dismiss-many", to: "repos/dependabot_alerts#dismiss_many", as: :repository_alerts_dismiss_many
    get  "security/dependabot/manifest-filter", to: "repos/dependabot_alerts#manifest_filter", as: :repository_alerts_manifest_filter
    get  "security/dependabot/package-filter", to: "repos/dependabot_alerts#package_filter", as: :repository_alerts_package_filter
    get  "security/dependabot/ecosystem-filter", to: "repos/dependabot_alerts#ecosystem_filter", as: :repository_alerts_ecosystem_filter
    get  "security/dependabot/severity-filter", to: "repos/dependabot_alerts#severity_filter", as: :repository_alerts_severity_filter
    get  "security/dependabot/closed-filter", to: "repos/dependabot_alerts#closed_as_filter", as: :repository_alerts_closed_as_filter
    get  "security/dependabot/filter-input-suggestions", to: "repos/dependabot_alerts#filter_input_suggestions", as: :repository_alerts_filter_input_suggestions

    get "security/dependabot/refresh", to: "repos/dependabot_alert_refresh#index", as: :refresh_repository_alerts

    constraints number: /\d+/ do
      get  "security/dependabot/:number", to: "repos/dependabot_alerts#show", as: :repository_alert
      post "security/dependabot/:number/bot-resolve", to: "repos/dependabot_alerts#bot_resolve", as: :repository_alert_bot_resolve
      get "security/dependabot/:number/bot-resolve-status", to: "repos/dependabot_alerts#bot_resolve_status", as: :repository_alert_bot_resolve_status
      get  "security/dependabot/:number/update-errors/:dependency_update_id", to: "repos/dependabot_alerts#update_error", as: :repository_alert_update_errors
      get  "security/dependabot/:number/update-logs/:dependency_update_id", to: "repos/dependabot_alerts#update_logs", as: :repository_alert_update_logs
      get  "security/dependabot/:number/events", to: "repos/dependabot_alerts#events", as: :repository_alert_events
      get  "security/dependabot/:number/hovercard", to: "hovercards/dependabot_alerts#show", as: :dependabot_alert_hovercard
      get  "security/dependabot/:number/dependency", to: "repos/dependabot_alerts_dependency#show", as: :repository_alert_dependency
    end

    get  "security/dependabot/*manifest_path/:package_name/:state", to: "repos/dependabot_alerts#grouped_show", as: :grouped_repository_alert, manifest_path: /.+/, package_name: /.+?/, state: /(open|closed)/

    # Redirects for old alert URLs that were previously under network/
    get  "network/alerts", to: "repos/dependabot_alerts#network_redirect"
    get  "network/alert/*manifest_path/:package_name/:state", to: "repos/dependabot_alerts#network_redirect", manifest_path: /.+/, package_name: /.+?/, state: /(open|closed)/
    get  "network/alert/*manifest_path/:package_name/:state/:update/:dependency_update_id", to: "repos/dependabot_alerts#network_redirect", manifest_path: /.+/, package_name: /.+?/, update: /(update-errors|update-logs)/

    if !GitHub.enterprise? || (GitHub.enterprise? && GitHub.repository_advisories_enabled?)
      constraints(id: AdvisoryDB.valid_ghsa_id_input_pattern) do
        get  "security/advisories",             to: "repos/advisories#index",       as: :repository_advisories
        get  "security/advisories/new",         to: "repos/advisories#new",         as: :new_repository_advisory
        post "security/advisories",             to: "repos/advisories#create",      as: :create_repository_advisory
        get  "security/advisories/:id",         to: "repos/advisories#show",        as: :repository_advisory
        put  "security/advisories/:id",         to: "repos/advisories#update"
        put  "security/advisories/:id/body",    to: "repos/advisories#update_body", as: :update_repository_advisory_body
        put  "security/advisories/:id/publish", to: "repos/advisories#publish",     as: :publish_repository_advisory
        put  "security/advisories/:id/request_cve", to: "repos/advisories#request_cve", as: :request_cve_repository_advisory
        post "security/advisories/partials/add_credit",  to: "repos/advisories#add_credit",  as: :add_repository_advisory_credit
        put "security/advisories/:id/accept_credit", to: "repos/advisories#accept_credit", as: :accept_repository_advisory_credit
        put "security/advisories/:id/decline_credit", to: "repos/advisories#decline_credit", as: :decline_repository_advisory_credit
        put "security/advisories/:id/decline_credit_and_block_user", to: "repos/advisories#decline_credit_and_block_user", as: :decline_repository_advisory_credit_and_block_user
        put "security/advisories/:id/accept_pvd", to: "repos/advisories#accept_pvd", as: :accept_repository_advisory_pvd

        put  "security/advisories/:id/open_workspace",      to: "repos/advisories#open_workspace",
                                                            as: :open_repository_advisory_workspace
        delete "security/advisories/:id/delete_workspace",  to: "repos/advisories#delete_workspace",
                                                            as: :delete_repository_advisory_workspace

        get  "security/advisories/:id/workspace", to: "repos/advisories#workspace",  as: :advisory_workspace

        get  "security/advisories/:id/merge_box", to: "repos/advisories#merge_box",  as: :advisory_workspace_merge_box
        post "security/advisories/:id/merge",     to: "repos/advisories#merge",      as: :merge_advisory_workspace

        match "security/advisories/:id/show_partial", to: "repos/advisories#show_partial",
                                                      as: :show_partial_repository_advisory,
                                                      via: [:get, :post]

        get "security/advisories/:id/autocomplete_collaborator", to: "repos/advisories#autocomplete_collaborator", as: :autocomplete_repository_advisory_collaborator
        post "security/advisories/:id/collaborators", to: "repos/advisories#add_collaborator", as: :add_repository_advisory_collaborator
        delete "security/advisories/:id/collaborators", to: "repos/advisories#remove_collaborator", as: :remove_repository_advisory_collaborator

        get "security/advisories/:id/edit_history_log", to: "repos/advisories#edit_history_log", as: :repository_advisory_edit_history_log

        post   "security/advisories/:id/comments",             to: "repos/advisory_comments#create", as: :create_repository_advisory_comment
        put    "security/advisories/:id/comments/:comment_id", to: "repos/advisory_comments#update", as: :update_repository_advisory_comment
        delete "security/advisories/:id/comments/:comment_id", to: "repos/advisory_comments#destroy"

        get "security/advisories/:id/comments/:comment_id/comment_actions_menu", to: "repos/advisory_comments_actions_menu#show", as: :repository_advisory_comment_actions_menu

        get "security/advisories/:id/issue-suggestions", to: "repos/advisory_comment_suggestions#issues", as: :repository_advisory_issue_suggestions
        get "security/advisories/:id/mention-suggestions",  to: "repos/advisory_comment_suggestions#mentions",  as: :repository_advisory_mention_suggestions
      end

      get  "security/token-scanning", to: redirect("/%{user_id}/%{repository}/security/secret-scanning")
      get  "security/token-scanning/:id", to: redirect("/%{user_id}/%{repository}/security/secret-scanning/%{id}")
      get  "security/token-scanning/:id/files", to: redirect("/%{user_id}/%{repository}/security/secret-scanning/%{id}/files")
    end

    constraints(number: /\d+/) do
      get "security/code-scanning", to: "repos/code_scanning#index", as: :repository_code_scanning_results
      get "security/code-scanning/refs", to: "repos/code_scanning#ref_list", as: :repository_code_scanning_results_ref_list
      get "security/code-scanning/rules", to: "repos/code_scanning#rule_list", as: :repository_code_scanning_results_rule_list
      get "security/code-scanning/search", to: "repos/code_scanning/linkable_search#index", as: :repository_code_scanning_linkable_search
      get "security/code-scanning/tags", to: "repos/code_scanning#tag_list", as: :repository_code_scanning_results_tag_list
      get "security/code-scanning/tools", to: "repos/code_scanning#tool_list", as: :repository_code_scanning_results_tool_list
      get "security/code-scanning/tool-status-banner", to: "repos/code_scanning/tool_status/banner#show", as: :repository_code_scanning_tool_status_banner
      get "security/code-scanning/available-assignees", to: "repos/code_scanning/available_assignees#index", as: :repository_code_scanning_available_assignees
      put "security/code-scanning/close", to: "repos/code_scanning#close", as: :repository_code_scanning_close
      put "security/code-scanning/reopen", to: "repos/code_scanning#reopen", as: :repository_code_scanning_reopen
      get "security/code-scanning/related-location", to: "repos/code_scanning#related_location_popover", as: :repository_code_scanning_related_location_popover
      get "security/code-scanning/:number", to: "repos/code_scanning#show", as: :repository_code_scanning_result
      post "security/code-scanning/:number/branches", to: "repos/code_scanning/branches#create", as: :create_code_scanning_branch
      patch "security/code-scanning/:number/links", to: "repos/code_scanning/alert_links#update", as: :update_code_scanning_alert_links
      patch "security/code-scanning/:number/assignees", to: "repos/code_scanning/assignees#update", as: :update_code_scanning_assignees
      post "security/code-scanning/:number/autofix/commits", to: "repos/code_scanning/autofix_commits#create", as: :repository_code_scanning_autofix_commits
      post "security/code-scanning/:number/generate-autofix", to: "repos/code_scanning/autofix#generate_autofix", as: :repository_code_scanning_generate_autofix
      get "security/code-scanning/:number/open-workspace-editor", to: "repos/code_scanning/autofix#open_workspace_editor", as: :repository_code_scanning_autofix_open_workspace_editor
      get "security/code-scanning/:number/code-paths", to: "repos/code_scanning#code_paths", as: :repository_code_scanning_code_paths
      get "security/code-scanning/:number/timeline", to: "repos/code_scanning#show_timeline", as: :repository_code_scanning_show_timeline
      get "security/code-scanning/:number/tracked_in/hovercard", to: "hovercards/issue_alert_links#tracked_in", as: :repository_code_scanning_show_tracked_in_hovercard
      get "security/code-scanning/:number/hovercard", to: "hovercards/code_scanning_alert#hovercard", as: :repository_code_scanning_alert_hovercard
      post "security/code-scanning/delete-configuration", to: "repos/code_scanning#mark_configuration_outdated", as: :repository_code_scanning_mark_configuration_outdated
      post "security/code-scanning/delete-configurations", to: "repos/code_scanning#batch_mark_configuration_outdated", as: :repository_code_scanning_batch_mark_configuration_outdated
    end

    get "security/code-scanning/tool-status", to: "repos/code_scanning/tool_status#index", as: :repository_code_scanning_results_tool_status
    scope "security/code-scanning/tool-status/:tool_name", format: :false, defaults: { format: :html }, constraints: { tool_name: /[^\/]+/ } do
      get "/", to: redirect("%{user_id}/%{repository}/security/code-scanning/tools/%{tool_name}/status/")
      get "/configurations/:configuration_group", to: redirect("%{user_id}/%{repository}/security/code-scanning/tools/%{tool_name}/status/configurations/%{configuration_group}")
      get "/configurations/:configuration_group/:configuration", to: redirect("%{user_id}/%{repository}/security/code-scanning/tools/%{tool_name}/status/configurations/%{configuration_group}/%{configuration}")
      get "/files", to: redirect("%{user_id}/%{repository}/security/code-scanning/tools/%{tool_name}/status/files")
      get "/rules.csv", to: redirect("%{user_id}/%{repository}/security/code-scanning/tools/%{tool_name}/status/rules.csv")
    end
    scope "security/code-scanning/tools/:tool_name/status", format: :false, defaults: { format: :html }, constraints: { tool_name: /.+/ } do
      get "/", to: "repos/code_scanning/tool_status#show", as: :repository_code_scanning_results_tool_status_show
      get "/configurations/:configuration_group", to: "repos/code_scanning/tool_status/configurations#index", as: :repository_code_scanning_results_tool_status_configurations
      get "/configurations/:configuration_group/:configuration", to: "repos/code_scanning/tool_status/configurations#show", as: :repository_code_scanning_results_tool_status_configurations_show
      get "/files", to: "repos/code_scanning/tool_status/files_extracted#show", as: :repository_code_scanning_results_tool_status_files_extracted, defaults: { format: "html" }
      get "/rules.csv", to: "repos/code_scanning/tool_status/rules#show", as: :repository_code_scanning_results_tool_status_rules
    end

    if !GitHub.enterprise? || (GitHub.enterprise? && GitHub.configuration_secret_scanning_enabled?)
      get "security/secret-scanning", to: "repos/secret_scanning/react_alerts#index", as: :repository_token_scanning_results
      get "security/secret-scanning/secret-type-options", to: "repos/secret_scanning/react_alerts#secret_type_options", as: :repository_react_alerts_secret_type_options
      get "security/secret-scanning/provider-options", to: "repos/secret_scanning/react_alerts#provider_options", as: :repository_react_alerts_provider_options
      put "security/secret-scanning/resolve-react", to: "repos/secret_scanning/react_alerts#resolve", as: :repository_react_alerts_resolve
      post "security/secret-scanning/closure-requests", to: "repos/secret_scanning/react_alerts#create_closure_requests", as: :repository_react_create_closure_requests

      constraints(id: /\d+/) do
        get "security/secret-scanning/:id", to: "repos/secret_scanning/react_alerts#show", as: :repository_react_alerts_show
        get "security/secret-scanning/:id/timeline", to: "repos/secret_scanning/react_alerts#timeline", as: :repository_react_alerts_timeline
        get "security/secret-scanning/:id/locations", to: "repos/secret_scanning/react_alerts#locations", as: :repository_react_alerts_locations
        get "security/secret-scanning/:id/org-access", to: "repos/secret_scanning/react_alerts#org_access", as: :repository_react_alerts_org_access
        put "security/secret-scanning/:id/validate-token", to: "repos/secret_scanning/react_alerts#validate_token", as: :repository_react_alerts_validate_token
        put "security/secret-scanning/:id/report", to: "repos/secret_scanning/react_alerts#report", as: :repository_react_alerts_report
        get "security/secret-scanning/:id/ai-adversarial-audit", to: "repos/secret_scanning/react_alerts#alert_ai_adversarial_audit", as: :repository_react_alerts_alert_ai_adversarial_audit
        get "security/secret-scanning/:id/ai-workflow-audit", to: "repos/secret_scanning/react_alerts#alert_ai_workflow_audit", as: :repository_react_alerts_alert_ai_workflow_audit
        get "security/secret-scanning/:id/ai-permission-audit", to: "repos/secret_scanning/react_alerts#alert_ai_permission_audit", as: :repository_react_alerts_alert_ai_permission_audit
        get "security/secret-scanning/:id/token-permissions", to: "repos/secret_scanning/react_alerts#get_token_permissions", as: :repository_react_alerts_get_token_permissions
        get "security/secret-scanning/:id/ai-autofix", to: "repos/secret_scanning/react_alerts#get_suggested_fix", as: :repository_react_alerts_get_suggested_fix
      end

      # Push protection
      get "security/secret-scanning/unblock-secret/success", to: "repos/secret_scanning/push_protection/bypass#success", as: :repository_secret_scanning_push_protection_bypass_success

      post ":parent_action/unblock-secret/*name(/*path)", to: "blob#add_push_protection_bypass", as: :repository_secret_scanning_push_protection_bypass_add_from_blob, name: /(.|\n)+/, via: [:post], format: false, defaults: { format: :html }

      constraints(placeholder_ksuid: /[a-zA-Z0-9]+/) do
        get "security/secret-scanning/unblock-secret/:placeholder_ksuid", to: "repos/secret_scanning/push_protection/react_bypass#index", as: :repository_secret_scanning_push_protection_bypass_placeholder
        post "security/secret-scanning/unblock-secret/:placeholder_ksuid", to: "repos/secret_scanning/push_protection/react_bypass#promote_bypass", as: :repository_secret_scanning_push_protection_promote_bypass
      end

      push_protection_controller = "repos/secret_scanning/push_protection"
      get "security/secret-scanning/push-protection/custom-message", to: "#{push_protection_controller}#custom_message", as: :repo_secret_scanning_push_protection_custom_message
    end

    # Secret Scanning Push Protection Delegated Bypass

    # Secret Scanning Delegated Bypass Reviewer Suggestions (points to repositories controller method)
    get      "settings/security_analysis/bypass_suggestions", to: "repos/secret_scanning/push_protection/delegated_bypass_reviewers#bypass_suggestions", as: :secret_scanning_bypass_reviewer_suggestions
    get      "settings/security_analysis/bypass_reviewers", to: "repos/secret_scanning/push_protection/delegated_bypass_reviewers#index", as: :repository_secret_scanning_get_bypass_reviewers
    post     "settings/security_analysis/bypass_reviewers", to: "repos/secret_scanning/push_protection/delegated_bypass_reviewers#create", as: :repository_secret_scanning_add_bypass_reviewer
    delete   "settings/security_analysis/bypass_reviewers", to: "repos/secret_scanning/push_protection/delegated_bypass_reviewers#destroy", as: :repository_secret_scanning_remove_bypass_reviewer

    # Secret Scanning Custom Patterns

    # Active routes
    get    "settings/security_analysis/custom_patterns/new", to: "repos/security_and_analysis/custom_patterns#new_custom_pattern", as: :new_custom_pattern
    post   "settings/security_analysis/custom_patterns/new", to: "repos/security_and_analysis/custom_patterns#create_custom_pattern", as: :create_custom_pattern
    delete "settings/security_analysis/custom_patterns", to: "repos/security_and_analysis/custom_patterns#delete_custom_patterns", as: :delete_custom_patterns
    post   "settings/security_analysis/test_custom_secret_scanning_pattern", to: "repos/security_and_analysis/custom_patterns#test_custom_secret_scanning_pattern", as: :test_custom_secret_scanning_pattern
    post   "settings/security_analysis/custom_patterns/get_generated_expressions", to: "repos/security_and_analysis/custom_patterns#get_generated_expressions", as: :get_generated_expressions

    constraints(id: /\d+/) do
      get    "settings/security_analysis/custom_patterns/:id", to: "repos/security_and_analysis/custom_patterns#show_custom_pattern", as: :show_custom_pattern
      post   "settings/security_analysis/custom_patterns/:id", to: "repos/security_and_analysis/custom_patterns#update_custom_pattern", as: :update_custom_pattern
      delete "settings/security_analysis/custom_patterns/:id", to: "repos/security_and_analysis/custom_patterns#delete_custom_pattern", as: :delete_custom_pattern
      post   "settings/security_analysis/custom_patterns/:id/settings", to: "repos/security_and_analysis/custom_patterns#update_custom_pattern_settings", as: :update_custom_pattern_settings
      post   "settings/security_analysis/custom_patterns/:id/cancel_dry_run", to: "repos/security_and_analysis/custom_patterns#cancel_custom_pattern_dry_run", as: :cancel_custom_pattern_dry_run
      get    "settings/security_analysis/get_custom_pattern_form_actions/:id", to: "repos/security_and_analysis/custom_patterns#get_custom_pattern_form_actions", as: :get_custom_pattern_form_actions
      get    "settings/security_analysis/get_custom_pattern_dry_run_results_by_cursor/:id", to: "repos/security_and_analysis/custom_patterns#get_custom_pattern_dry_run_results_by_cursor", as: :get_custom_pattern_dry_run_results_by_cursor
      get    "settings/security_analysis/custom_patterns/:id/metrics/alerts", to: "repos/security_and_analysis/custom_patterns#get_alert_metrics", as: :get_custom_pattern_alert_metrics
      get    "settings/security_analysis/custom_patterns/:id/metrics/push_protection", to: "repos/security_and_analysis/custom_patterns#get_push_protection_metrics", as: :get_custom_pattern_push_protection_metrics
    end

    # Deprecated routes - retained for redirection in case users have bookmarked links.
    get    "settings/security_analysis/new_custom_secret_scanning_pattern", to: redirect("settings/security_analysis/custom_patterns/new")
    get    "settings/security_analysis/view_custom_pattern_dry_run/:id", to: redirect("settings/security_analysis/custom_patterns/:id")
    get    "settings/security_analysis/edit_custom_secret_scanning_pattern/:id", to: redirect("settings/security_analysis/custom_patterns/:id")
    post   "settings/security_analysis/cancel_custom_pattern_dry_run/:id", id: /\d+/, to: redirect("settings/security_analysis/custom_patterns/:id/cancel_dry_run")

    get "security",               to: "repos/security#overview",      as: :repository_security_overview
    get "security/overall-count", to: "repos/security#overall_count", as: :repository_security_overall_count
    get "security/counts",       to: "repos/security#counts",         as: :repository_security_counts
    get "security/policy",        to: "repos/security#policy",        as: :repository_security_policy

    ##
    # PublicKeysController
    get    "deploy_keys",            to: "public_keys#index",   as: :deploy_keys
    post   "deploy_keys",            to: "public_keys#create"
    put    "deploy_keys/:id",        to: "public_keys#update",  as: :deploy_key,        id: /[^\/.?]+/
    delete "deploy_keys/:id",        to: "public_keys#destroy",                            id: /[^\/.?]+/
    post   "deploy_keys/:id/verify", to: "public_keys#verify",  as: :verify_deploy_key

    ##
    # Deferred Diff Lines
    get   "pull/:pull_id/review_thread_syntax_highlighted_diff_lines", to: "review_thread_syntax_highlighted_diff_lines#index", as: :pull_request_review_thread_syntax_highlighted_diff_lines
    get   "diffs/:range", to: "syntax_highlighted_diff_entries#index",
      as: :syntax_highlighted_diff_entries,
      constraints: { range: /[a-f0-9]{40}\.\.[a-f0-9]{40}/ },
      defaults: { format: :json },
      format: false

    ##
    # Pull Request Review Comments
    get    "pull/:pull_id/review_comment/:id",          to: "pull_request_review_comments#show", id: /\d+/, defaults: { raw: true }, as: :show_review_comment
    delete "pull/:pull_id/review_comment/:id",          to: "pull_request_review_comments#destroy", id: /\d+/,  as: :destroy_review_comment
    put    "pull/:pull_id/review_comment/:id",          to: "pull_request_review_comments#update",  id: /\d+/,  as: :update_review_comment
    post   "pull/:pull_id/review_comment/create",       to: "pull_request_review_comments#create",                 as: :create_review_comment
    get    "pull/:pull_id/review_comment/:id/excerpt",  to: "pull_request_review_comments#excerpt", id: /\d+/,  as: :review_comment_excerpt
    get    "pull/:pull_id/review_comment/suggestion_button", to: "pull_request_review_comments#suggestion_button", as: :review_comment_suggestion_button
    get    "pull/:pull_id/review_comment/:id/actions",    to: "pull_request_review_comments#actions",     as: :review_comment_actions
    get    "pull/:pull_id/review_comment/:id/edit_form",  to: "pull_request_review_comments#edit_form",   as: :review_comment_edit_form
    put    "pull/:pull_id/review_comment/:id/minimize",   to: "pull_request_review_comments#minimize",    as: :review_comment_minimize
    put    "pull/:pull_id/review_comment/:id/unminimize", to: "pull_request_review_comments#unminimize",  as: :review_comment_unminimize


    put    "pull/:pull_id/threads/:thread_id/resolve", to: "pull_request_review_thread_resolutions#create", as: :resolve_review_thread
    delete    "pull/:pull_id/threads/:thread_id/unresolve", to: "pull_request_review_thread_resolutions#destroy", as: :unresolve_review_thread
    get    "pull/:pull_id/threads/:thread_id",               to: "pull_request_review_thread_resolutions#show", as: :review_thread
    get    "pull/:pull_id/threads/:thread_id/more_comments", to: "pull_request_review_thread_resolutions#more_comments", as: :review_thread_more_comments

    ##
    # Pull Request Review
    put    "pull/:pull_id/reviews", to: "pull_request_review_events#create", as: :update_review
    post   "pull/:pull_id/reviews/quick-approval", to: "pull_request_review_events#quick_approve", as: :quick_approve_review
    get    "pull/:pull_id/reviews/:review_id", to: "pull_request_reviews#show", as: :pull_request_review
    put    "pull/:pull_id/reviews/:review_id/unminimize", to: "pull_request_reviews#unminimize", as: :pull_request_review_unminimze
    put    "pull/:pull_id/reviews/:review_id/minimize", to: "pull_request_reviews#minimize", as: :pull_request_review_minimize
    put    "pull/:pull_id/reviews/:review_id/update", to: "pull_request_reviews#update", as: :pull_request_review_update
    get    "pull/:pull_id/reviews/:review_id/update/edit_form", to: "pull_request_reviews#edit_form", as: :pull_request_review_edit_form
    get    "pull/:pull_id/reviews/:review_id/more_threads", to: "pull_request_reviews#more_threads", as: :pull_request_review_more_threads
    put    "pull/:pull_id/reviews/dismiss/:id", to: "pull_request_review_events#dismiss", as: :dismiss_review

    post "pull/:pull_id/file_review", to: "user_reviewed_files#create", as: :user_review_file
    delete "pull/:pull_id/file_review", to: "user_reviewed_files#destroy"

    get    "pull/:id/suggested-reviewers",        to: "suggested_reviewers#show", as: :suggested_reviewers
    get    "pull/new/suggested-reviewers/:range", to: "suggested_reviewers#show", as: :suggested_reviewers_range, range: /.+/

    get  "pull/new/review-requests/team-size-check", to: "review_requests#team_size_check", as: :review_request_team_size_check_new
    get  "pull/:id/review-requests/team-size-check", to: "review_requests#team_size_check", as: :review_request_team_size_check
    post "pull/new/review-requests/:range", to: "review_requests#create_new", as: :create_review_request_new, range: /.+/
    get  "pull/new/review-requests/:range", to: "review_requests#menu", as: :reviewers_menu_content_new, range: /.+/
    post "pull/:id/review-requests", to: "review_requests#create", as: :create_review_request
    post "pull/:id/re-request-review", to: "review_requests#re_request_review", as: :re_request_review
    get  "pull/:id/review-requests", to: "review_requests#menu", as: :reviewers_menu_content

    ##
    # Code Scanning Autofix
    post  "pull/:pull_id/code_scanning/autofix", to: "repos/code_scanning/autofix#apply_suggested_fix", as: :pull_request_code_scanning_autofix
    post  "pull/:pull_id/code_scanning/alerts/:alert_number/autofix/new_feedback", to: "repos/code_scanning/autofix#feedback" # TODO remove this after a while
    post  "pull/:pull_id/code_scanning/alerts/:alert_number/autofix/feedback", to: "repos/code_scanning/autofix#feedback", as: :pull_request_code_scanning_autofix_feedback
    get  "pull/:pull_id/code_scanning/alerts/:alert_number/autofix/review_comment_partial", to: "repos/code_scanning/autofix#review_comment_partial", as: :pull_request_code_scanning_autofix_review_comment_partial

    ##
    # Dependabot Autofix
    post "pull/:pull_id/dependabot/autofix", to: "repos/dependabot/autofix#create", as: :pull_request_dependabot_autofix
    get  "pull/:pull_id/dependabot/autofix/review_comment_partial", to: "repos/dependabot/autofix#review_comment_partial", as: :pull_request_dependabot_autofix_review_comment_partial
    post "pull/:pull_id/dependabot/autofix/:autofix_job_id/feedback", to: "repos/dependabot/autofix/feedback#create", as: :pull_request_dependabot_autofix_feedback

    ##
    # Auto-merge Requests
    post "pull/:pull_id/auto_merge_requests", to: "auto_merge_requests#create", as: :create_auto_merge_request
    delete "pull/:pull_id/auto_merge_requests", to: "auto_merge_requests#destroy", as: :destroy_auto_merge_request

    ##
    # Pull Requests
    match  "pull/new/:range",       to: "pull_requests#new",                 as: :new_pull_request,           via: [:get, :post],  range: /.*/
    match  "pull/new",              to: "pull_requests#new",                                                    via: [:get, :post]
    post   "pull/create",           to: "pull_requests#create",              as: :create_pull_request

    draw :pull_requests_react

    # ConflictedFiles
    get    "pull/:id/conflict",              to: "conflicted_files#show"
    get    "pull/:id/conflicts",             to: "pull_requests#resolve_conflicts", as: :resolve_conflicts
    post   "pull/:id/conflicts/resolve",     to: "conflicted_files#resolve"

    get    "pull/:id/show_from_project", to: "issues#show_from_project", pulls_only: true, id: /\d+/, as: :show_pull_request_from_project
    match  "pull/:id/show_partial", to: "pull_requests#show_partial",        as: :show_partial_pull_request,  via: [:get, :post]
    get    "pull/:id/show_partial_comparison", to: "pull_requests#show_partial_comparison", as: :show_partial_pull_request_comparison
    get    "pull/:id/show_toc",     to: "pull_requests#show_toc",            as: :show_pull_request_toc
    get    "pull/:id/conversations_menu", to: "pull_requests#conversations_menu", as: :show_pull_request_conversations_menu
    post   "pull/:id/cleanup",      to: "pull_requests#cleanup",             as: :cleanup_pull_request
    post   "pull/:id/undo_cleanup", to: "pull_requests#undo_cleanup",        as: :undo_cleanup_pull_request
    post   "pull/:id/cleanup_codespaces",      to: "pull_requests#cleanup_codespaces",             as: :cleanup_codespaces
    post   "pull/:id/merge",        to: "pull_requests#merge",               as: :merge_pull_request
    get    "pull/:id/post_merge",   to: "pull_requests#post_merge",          as: :pull_request_post_merge
    post   "pull/:id/update_branch",  to: "pull_requests#update_branch",     as: :update_branch_pull_request
    post   "pull/:id/revert",       to: "pull_requests#revert",              as: :revert_pull_request
    match  "pull/:id/merge-button", to: "pull_requests#merge_button",        as: :merge_button,               via: [:get, :post]
    get    "pull/:id/open_with_menu", to: "pull_requests#open_with_menu",    as: :pull_request_open_with_menu, id: /\d+/
    get    "pull/:id/code_menu_contents", to: "pull_requests#code_menu_contents", as: :pull_request_code_menu_contents, id: /\d+/
    get    "pull/:id/hovercard",    to: "hovercards/issues_and_pull_requests#show", id: /\d+/
    get    "pull/:id/changes_since_last_review", to: "pull_requests#changes_since_last_review", as: :pull_changes_since_last_review
    get    "pull/:id/timeline_more_items",       to: "pull_requests#timeline_more_items", id: /\d+/, as: :pull_timeline_more_items
    get    "pull/:id/ready",        to: "pull_requests#ready_for_review_from_cli", id: /\d+/
    post   "pull/:id/diffview", to: "pull_request_diff_view#update_preferences",  as: :pull_diff_view_preferences, id: /\d+/
    get    "pull/:id/files",        to: "pull_requests#files",               as: :pull_request_files, id: /\d+/, defaults: { tab: "files" }
    get    "pull/:id/files/:range", to: "pull_requests#files",               as: :pull_request_files_with_range, id: /\d+/, range: /(?:[^.]|\.{2,})+/, defaults: { tab: "files" }
    get    "pull/:id/commits",      to: "pull_requests#commits",             as: :pull_request_commits, id: /\d+/, defaults: { tab: "commits" }
    get    "pull/:id/commits/:range",  to: "pull_requests#commits",          as: :pull_request_commits_with_range, id: /\d+/, range: /(?:[^.]|\.{2,})+/, defaults: { tab: "commits" }
    get    "pull/:id/deferred_commits_data", to: "pull_requests#deferred_commits_data", as: :pull_requests_deferred_commits_data, id: /\d+/, format: "json"
    get    "pull/:id/checks",       to: "pull_requests#checks",              as: :pull_request_checks, id: /\d+/, defaults: { tab: "checks" }
    get    "pull/:id/walkthrough",  to: "hypersight#show"
    get    "pull/:id/:tab/:range",  to: "pull_requests#show",                as: :pull_request_show, id: /\d+/, tab: /commits|files/, range: /(?:[^.]|\.{2,})+/
    get    "pull/:id/orchestration/:orchestration_id", to: "pull_requests/orchestration#show", as: :pull_request_orchestration_status

    # Pull request partials
    get    "pull/:id/partials/deployments_box", to: "pull_request_partials#deployments_box", as: :pull_request_deployments_box_partial
    get    "pull/:id/partials/description_branches_dropdown", to: "pull_request_partials#description_branches_dropdown", as: :pull_request_description_branches_dropdown_partial
    get    "pull/:id/partials/form_actions", to: "pull_request_partials#form_actions", as: :pull_request_form_actions_partial
    get    "pull/:id/partials/merging", to: "pull_request_partials#merging", as: :pull_request_merging_partial
    get    "pull/:id/partials/sidebar", to: "pull_request_partials#sidebar", as: :pull_request_sidebar_partial
    get    "pull/:id/partials/state", to: "pull_request_partials#state", as: :pull_request_state_partial
    get    "pull/:id/partials/state_button_wrapper", to: "pull_request_partials#state_button_wrapper", as: :pull_request_state_button_wrapper_partial
    get    "pull/:id/partials/tabs", to: "pull_request_partials#tabs", as: :pull_request_tabs_partial
    get    "pull/:id/partials/title", to: "pull_request_partials#title", as: :pull_request_title_partial
    get    "pull/:id/partials/deployed_event/:event_id", to: "pull_request_partials#deployed_event", as: :pull_request_deployed_event_partial
    get    "pull/:id/partials/commit_status_checks", to: "pull_request_partials#commit_status_checks", as: :pull_request_commit_status_checks_partial
    get    "pull/:id/partials/changed_commits", to: "pull_request_partials#changed_commits", as: :pull_request_changed_commits_partial
    get    "pull/:id/partials/reviews/:review_id", to: "pull_request_partials#review", as: :pull_request_review_partial
    get    "pull/:id/partials/unread_timeline", to: "pull_request_partials#unread_timeline", as: :pull_request_unread_timeline_partial
    get    "pull/:id/partials/body", to: "pull_request_partials#body", as: :pull_request_body_partial
    get    "pull/:id/partials/commit_status_icon", to: "pull_request_partials#commit_status_icon", as: :pull_request_commit_status_icon_partial
    get    "pull/:id/partials/file_tree", to: "pull_request_partials#file_tree", as: :pull_request_file_tree_partial
    get    "pull/:id/partials/processing_indicator", to: "pull_request_partials#processing_indicator", as: :pull_request_processing_indicator_partial, format: :json
    get    "pull/:id/partials/links", to: "pull_request_partials#links", as: :pull_request_links_partial
    get    "pull/:id/partials/closing_issue_references_empty_text", to: "pull_request_partials#closing_issue_references_empty_text", as: :pull_request_closing_issue_references_empty_text_partial

    get    "pull/:id/:tab",         to: "pull_requests#show",                as: :pull_request_tab,     id: /\d+/ # WARNING This will take precedence over any GET `/pull/:id/foo` route defined after it
    get    "pull/*id.diff",         to: "pull_requests#diff",                as: :pull_request_diff,    id: /.+/
    get    "pull/*id.patch",        to: "pull_requests#patch",               as: :pull_request_patch,   id: /.+/
    get    "pull/*id",              to: "pull_requests#show",                as: :show_pull_request,    id: /.+/
    post   "pull/:id/comment",      to: "pull_requests#comment",             as: :comment_pull_request
    post   "pull/:id/dismiss_protip", to: "pull_requests#dismiss_protip",    as: :dismiss_protip_pull_request, id: /.+/
    post   "pull/:id/change_base",  to: "pull_requests#change_base",         as: :change_pull_base
    post   "pull/:id/set_collab",   to: "pull_requests#set_collab",          as: :pull_request_collaborator_edits_setting

    # Pull Request Survey
    unless GitHub.enterprise?
      get "/pull-requests-survey/fragment", to: "pull_requests/survey#fragment", as: :pull_requests_survey_fragment
      post "/pull-requests-survey/answer", to: "pull_requests/survey#answer", as: :pull_requests_survey_answer
      post "/pull-requests-survey/dismiss", to: "pull_requests/survey#dismiss", as: :pull_requests_survey_dismiss
    end

    ##
    # Issue and PR timelines
    get    "timeline", to: "timeline#show", as: :show_timeline
    get    "timeline_focused_item", to: "timeline#timeline_focused_item"
    get    "related_repositories", to: "related_repositories#index", as: :related_repositories

    ##
    # Releases / Tags
    get    "releases/download/*name(/*path)", to: "releases#download", as: :download_release, name: /.+/, format: false
    get    "releases/new",                    to: "releases#new",      as: :new_release
    post   "releases",                        to: "releases#create",   as: :create_release
    post   "releases/preview",                to: "releases#preview",  as: :preview_release

    # new routes supporting tag names with /
    get    "releases/edit/*name",              to: "releases#edit",            as: :edit_release,     name: /.+/, format: false, defaults: { format: :html }
    put    "releases/tag/*name",               to: "releases#update",          as: :update_release,   name: /.+/, format: false, defaults: { format: :html }
    delete "releases/tag/*name",               to: "releases#destroy",         as: :destroy_release,  name: /.+/
    get    "releases/tag/*name",               to: "releases#show",            as: :show_release,     name: /.+/, format: false, defaults: { format: :html }
    get    "releases/latest",                  to: "releases#latest",          as: :latest_release
    get    "releases/latest/download(/*path)", to: "releases#download_latest", format: false
    get    "releases/notes",                   to: "releases#generate_notes",  as: :generate_notes
    get    "releases/expanded/*name",          to: "releases#expanded_card",   as: :expanded_card, name: /.+/, format: false, defaults: { format: :html }
    get    "releases/expanded_assets/*name",   to: "releases#expanded_assets", as: :expanded_assets, name: /.+/, format: false, defaults: { format: :html }

    # legacy routes supporting tag slugs
    slug_regex = /[^\/]+/
    get    "releases/:name/edit",                   to: "releases#edit",     name: slug_regex
    put    "releases/:name",                        to: "releases#update",   name: slug_regex, format: false, defaults: { format: :html }
    delete "releases/:name",                        to: "releases#destroy",  name: slug_regex
    get    "releases/:name",                        to: "releases#show",     name: slug_regex, format: false, defaults: { format: :html }
    get    "releases/:name/:asset_id/:unused_name", to: "releases#download", name: slug_regex, unused_name: /.+/, asset_id: /\d+/

    get    "releases",      to: "releases#index",        as: :releases
    get    "releases.atom", to: "releases#index",        as: :releases_feed,  format: "atom"
    get    "tags/check",    to: "releases#check_tag",    as: :check_tag
    post   "tags",          to: "releases#create_tag",   as: :create_tag
    get    "tags",          to: "releases#tag_history",  as: :tags
    get    "tags.atom",     to: "releases#tag_history",  as: :tags_feed,      format: "atom"

    ##
    # Search
    get    "search",            to: "repository_search#index", as: :repo_search
    get    "search/count",      to: "repository_search#count", as: :repo_search_count

    get    "upload/(:name)(/*path)", to: "repository_uploads#index", as: :repo_uploads, name: /.+/
    post   "upload",                 to: "repository_uploads#create"
    delete "upload",                 to: "repository_uploads#destroy"
    post   "upload/show-secret-scanning-push-protection-bypass", to: "repository_uploads#show_secret_scanning_push_protection_bypass", as: :repo_uploads_show_secret_scanning_push_protection_bypass
    post   "upload/add-secret-scanning-push-protection-bypass", to: "repository_uploads#add_secret_scanning_push_protection_bypass", as: :repo_uploads_add_secret_scanning_push_protection_bypass, via: [:post], format: false, defaults: { format: :html }

    ##
    # NotificationsController
    get   "notifications",
            to: redirect { |params, request|
              if request.query_parameters[:list_type] == "team"
                "/notifications?query=is%3Ateam-discussion"
              else
                "/notifications?query=repo%3A#{params[:user_id]}%2F#{params[:repository]}"
              end
            },
            constraints: NOTIFICATIONS_V2_REDIRECT_CONSTRAINT,
            as: :repository_notifications_redirect

    get   "subscription",                 to: "notifications#subscription",          as: :repository_subscription
    get   "unsubscribe_via_email/:data",  to: "notifications#unsubscribe_via_email", as: :repository_unsubscribe_via_email
    get   "notifications",                to: "notifications#index",                 as: :repository_notifications
    post  "notifications/mark",           to: "notifications#mark_as_read",          as: :mark_list_notifications

    ##
    # WikiController
    post   "wiki/_preview",                     to: "wiki#preview",                          id: /[^\/]+/, version_list: /.*/
    get    "wiki",                              to: "wiki#index",        as: :wikis
    post   "wiki",                              to: "wiki#create",       as: nil
    put    "wiki/:id",                          to: "wiki#update",                           id: /[^\/]+/
    delete "wiki/:id",                          to: "wiki#destroy",                          id: /[^\/]+/
    post   "wiki/:id/_compare(/:version_list)", to: "wiki#compare",                          id: /[^\/]+/, version_list: /.*/
    get    "wiki/:id/_compare(/:version_list)", to: "wiki#compare",                          id: /[^\/]+/, version_list: /.*/
    get    "wiki/_history",                     to: "wiki#history"
    post   "wiki/_compare(/:version_list)",     to: "wiki#compare",                                                version_list: /.*/
    get    "wiki/_compare(/:version_list)",     to: "wiki#compare",                                                version_list: /.*/
    get    "wiki/_pages",                       to: "wiki#pages",        as: :wiki_pages
    get    "wiki/_new",                         to: "wiki#new",          as: :new_wiki
    post   "wiki/_revert/:older/:newer",        to: "wiki#revert"
    get    "wiki/:id/_edit",                    to: "wiki#edit",         as: :edit_wiki,  id: /[^\/]+/
    get    "wiki/:id/_current",                 to: "wiki#current",      as: :wiki_current, id: /[^\/]+/
    get    "wiki/:id/_history",                 to: "wiki#history",                          id: /[^\/]+/
    get    "wiki/:id/_toc",                     to: "wiki#toc",          as: :wiki_toc,      id: /[^\/]+/
    post   "wiki/:id/_revert/:older/:newer",    to: "wiki#revert",                           id: /[^\/]+/
    get    "wiki/:id",                          to: "wiki#show",         as: :wiki,       id: /[^\/]+/, defaults: { format: "html" }
    get    "wiki/:id/:version(/*path)",         to: "wiki#show",                             id: /[^\/]+/, format: false
    get    "wiki/*path",                        to: "wiki#show",                                              format: false
    get    "wikis(/*args)",                     to: "wiki#redirect"

    ##
    # Repositories
    match  "zipball/:name",         to: "tree#zipball",          as: :zipball_legacy, via: [:get, :post], name: /.+/
    match  "tarball/:name",         to: "tree#tarball",          as: :tarball_legacy, via: [:get, :post], name: /.+/
    match  "archive/*name.tar.gz",  to: "tree#archive",          as: :tarball,        via: [:get, :post], name: /.+/, format: false, _format: "tar.gz"
    match  "archive/*name.zip",     to: "tree#archive",          as: :zipball,        via: [:get, :post], name: /.+/, format: false, _format: "zip"

    get    "check",                     to: "tree#check",                    as: :check_repo
    post   "dismiss-tree-finder-help",  to: "tree#dismiss_tree_finder_help", as: :dismiss_list_help
    match  "find/:name",                to: "tree#find",                     as: :tree_find,    name: /.+/,  via: [:get, :post]
    match  "tree-list/:name",           to: "tree#list",                     as: :tree_list,    name: /.+/,  via: [:get, :post]

    # Code navigation routes
    get    "find-react-definition",     to: "code_nav#react_definition",  as: :code_nav_react_definition,  format: :json
    get    "find-react-references",     to: "code_nav#react_references",  as: :code_nav_react_references,  format: :json


    match "tree/delete/*name(/*path)", to: "tree#delete", as: :delete_directory, name: /(.|\n)+/, via: [:get, :post], format: false, defaults: { format: :html }
    delete "tree/*name(/*path)", to: "tree#destroy", as: :destroy_directory, name: /(.|\n)+/, format: false, defaults: { format: :html }

    get    "refs/*name(/*path)",          to: "refs#index",          as: :refs,               name: /.+/,                          format: false, defaults: { format: :html }
    get    "refs",                        to: "refs#ref_list",       as: :refs_ref_list
    get    "refs-menu",                   to: "refs#ref_list_select_menu", as: :ref_list_select_menu
    get    "refs-tags/*name(/*path)",     to: "refs#tags",           as: :refs_tags,          name: /.+/,                          format: false, defaults: { format: :html }

    get "tree-commit-info/*name(/*path)",  to: "files#commit_info",               as: :tree_commit_info,          name: /.+/, format: :json
    get "branch-infobar/*name(/*path)",    to: "files#branch_infobar",            as: :branch_infobar,            name: /.+/, format: :json
    get "tree/*name(/*path)",              to: "files#disambiguate",              as: :tree,                      name: /.+/, format: false, defaults: { format: :html }
    get "latest-commit/:name(/*path)",     to: "files#latest_commit",             as: :latest_commit,             name: /.+/, format: :json
    get "file-contributors/:name(/*path)", to: "files#contributors",              as: :file_contributors,         name: /.+/, format: :json
    get "recently-touched-branches",       to: "files#recently_touched_branches", as: :recently_touched_branches,             format: :json
    get "branch-count",                    to: "files#branch_count",              as: :branch_count,              name: /.+/, format: false, defaults: { format: :html }
    get "tag-count",                       to: "files#tag_count",                 as: :tag_count,                 name: /.+/, format: false, defaults: { format: :html }
    get "branch-and-tag-count",            to: "files#branch_and_tag_count",      as: :branch_and_tag_count,      name: /.+/
    get "overview-files/:name",            to: "files#overview_files",            as: :overview_files,            name: /.+/, format: :json

    match  "blame/*name(/*path)",         to: "blob#blame",          as: :blame,              name: /(.|\n)+/,  via: [:get, :post],  format: false, defaults: { format: :html }
    match  "tree-save/*name(/*path)",     to: "blob#save",           as: :file_save,          name: /(.|\n)+/,  via: [:get, :post],  format: false, defaults: { format: :html }
    match  "new/*name(/*path)",           to: "blob#new",            as: :new_file,           name: /(.|\n)+/,  via: [:get, :post],  format: false, defaults: { format: :html }
    match  "create/*name(/*path)",        to: "blob#create",         as: :create_file,        name: /(.|\n)+/,  via: [:get, :post],  format: false, defaults: { format: :html }
    match  "edit/*name(/*path)",          to: "blob#edit",           as: :file_edit,          name: /(.|\n)+/,  via: [:get, :post],  format: false, defaults: { format: :html }
    match  "delete/*name(/*path)",        to: "blob#delete",         as: :delete_file,        name: /(.|\n)+/,  via: [:get, :post],  format: false, defaults: { format: :html }
    delete "blob/*name(/*path)",          to: "blob#destroy",        as: :destroy_file,       name: /(.|\n)+/,                          format: false, defaults: { format: :html }
    match  "file-edit/:name(/*path)",     to: "blob#edit",                                    name: /(.|\n)+/,  via: [:get, :post],  format: false, defaults: { format: :html }
    match  "preview/*name(/*path)",       to: "blob#preview",        as: :preview_edit,       name: /(.|\n)+/,  via: [:get, :post]
    match  "raw/*name(/*path)",           to: "blob#raw",            as: :raw_blob,           name: /(.|\n)+/,  via: [:get, :post],  format: false, defaults: { format: :html }
    get    "blob/-/*path",                to: "blob#redirect_to_default_branch", as: :default_branch_blob,                         format: false, defaults: { format: :html }
    get    "file/*path",                  to: "blob#redirect_to_default_branch", as: :default_branch_file,                         format: false, defaults: { format: :html }
    get    "blob/*name(/*path)",          to: "blob#show",           as: :blob,               name: /(.|\n)+/,                     format: false, defaults: { format: :html }
    get    "deferred-metadata/*name(/*path)", to: "blob#deferred_metadata",           as: :deferred_metadata,               name: /(.|\n)+/,                     format: false, defaults: { format: :json }
    get    "deferred-ast/*name(/*path)", to: "blob#deferred_ast",           as: :deferred_ast,               name: /(.|\n)+/,                     format: false, defaults: { format: :json }
    get    "detect_language",             to: "blob#detect_language", as: :detect_blob_language,                                   format: "json"
    get    "sidepanel-metadata",          to: "blob#sidepanel_metadata", as: :sidebar_metadata,                                    format: "json"
    get    "codeowners-badge/*name(/*path)",    to: "codeowners#index",     as: :codeowners_badge,  name: /(.|\n)+/,               format: false, defaults: { format: :html }
    get    "codeowners-validity/*name(/*path)", to: "codeowners#validity",  as: :codeowners_validity, name: /(.|\n)+/,             format: false
    post   "auto-fork/*name",           to: "blob#auto_fork_for_editor", as: :auto_fork, name: /(.|\n)+/

    get "contributors/*name(/*path)", to: "blob#contributors", as: :blob_contributors, name: /(.|\n)+/, format: false, defaults: { format: :html }
    get "contributors-list/*name(/*path)", to: "blob#contributors_list", as: :blob_contributors_list, name: /(.|\n)+/, format: false, defaults: { format: :html }

    match  "blob_excerpt/:oid",           to: "blob#excerpt",        as: :blob_excerpt,       oid: /[0-9a-f]{40}/, via: [:get, :post]
    get    "blob_expand/:oid",            to: "blob#expand",         as: :blob_expand,       oid: /[0-9a-f]{40}/

    get    "files/:id(/*path)",    to: "attachments/legacy_repository_files#show", as: :legacy_repository_file, format: false
    get    "assets/:user/:guid",   to: "attachments/legacy_user_assets#show",      as: :legacy_user_file,       format: false

    get "hovercard",               to: "hovercards/repositories#show",     as: :repository_hovercard

    get "hovercards/citation",    to: "hovercards/repositories/citations#show", as: :repository_citation_hovercard
    get "hovercards/citation/sidebar_partial", to: "hovercards/repositories/citations#sidebar_partial", as: :repository_citation_sidebar_partial
    get "citation_file_template", to: "hovercards/repositories/citations#file_template",             as: :repository_citation_template, template: /[\w\.\+-]+/
    get "my_forks_menu_content",  to: "repositories#my_forks_menu_content",             as: :my_forks_menu_content

    post   "star",                to: "tree#star",                         as: :star_repository,        via: [:get, :post]
    post   "unstar",              to: "tree#unstar",                       as: :unstar_repository,      via: [:get, :post]
    match  "watchers",            to: "repositories#watchers",             as: :watchers,               via: [:get, :post]
    match  "stargazers",          to: "repositories#stargazers",           as: :stargazers_repository,  via: [:get, :post]
    match  "stargazers/you_know", to: "repositories#stargazers_you_know",  as: :stargazers_you_know,    via: [:get, :post]
    match  "contributors",        to: "repositories#contributors",         as: :contributors,           via: [:get, :post]
    match  "contributors_list",   to: "repositories#contributors_list",    as: :contributors_list,      via: [:get, :post]
    match  "used_by_list",        to: "repositories#used_by_list",         as: :used_by_list,           via: [:get, :post]
    match  "environment_status",  to: "repositories#environment_status",   as: :environment_status,     via: [:get, :post]
    match  "packages_list",       to: "repositories#packages_list",        as: :packages_list,          via: [:get, :post]
    match  "show_partial",        to: "tree#show_partial",                 as: :show_partial_tree,      via: [:get, :post]
    match  "noooooope",           to: "repositories#no_content",           as: :no_content,             via: [:get, :post]
    match  "nooooope",            to: "repositories#no_content_tabs",      as: :no_content_tabs,        via: [:get, :post]

    post "stats", to: "repository_stats#create", as: :repository_stats

    match  "pulse(/:period)",                 to: "repositories#pulse",                as: :pulse,                period: "weekly",  via: [:get, :post], format: false
    match  "pulse_committer_data(/:period)",  to: "repositories#pulse_committer_data", as: :pulse_committer_data, period: "weekly",  via: [:get, :post]
    get  "pulse_diffstat_summary",  to: "repositories#pulse_diffstat_summary", as: :pulse_diffstat_summary

    get    "people",                           to: "repos/access#index",                   as: :repo_people_index
    get    "collaborators",                    to: "repos/access#collaborators",           as: :repo_people_collaborators
    get    "people/export",                    to: "repos/access#export",                  as: :repo_people_export

    ## Deployments

    # Environment pinning
    post "environments/:environment/pin", to: "pinned_environments#create", as: :pin_environment
    delete "environments/:environment/pin", to: "pinned_environments#destroy", as: :unpin_environment

    # Filter suggestions for new deployments view
    get "deployments/filter-suggestions/environments", to: "repository_deployments/filter_suggestions#environments", as: :deployments_filter_suggestions_for_environments
    get "deployments/filter-suggestions/refs", to: "repository_deployments/filter_suggestions#refs", as: :deployments_filter_suggestions_for_refs
    get "deployments/filter-suggestions/users", to: "repository_deployments/filter_suggestions#users", as: :deployments_filter_suggestions_for_users

    match  "deployments", to: "repository_deployments#deployments", as: :deployments, via: [:get]
    match  "deployments/activity_log", to: "repository_deployments#deployments_activity_log", as: :deployments_activity_log, via: [:get]
    get  "deployments/:environment", environment: /[^\/]+/, format: false, to: "repository_deployments#environment_deployments", as: :environment_deployments
    match  "full_associated_pulls/:deployment_id", to: "repositories#full_associated_pulls", as: :full_associated_pulls, via: [:get]
    match  "compact_associated_pulls/:deployment_id", to: "repositories#compact_associated_pulls", as: :compact_associated_pulls, via: [:get]

    match "deployments_environment", to: "repositories#deployments_environment_state", as: :deployments_environment_state, via: [:get]

    match  "environments/approve_or_reject", to: "environments#approve_or_reject_gate_requests", as: :approve_or_reject_gate_requests, via: [:post]
    match  "environments/skip", to: "environments#skip_pending_gate_requests", as: :skip_pending_gate_requests, via: [:post]

    # Attestations
    match  "attestations", to: "repository_attestations#index", as: :attestations, via: [:get]
    match  "attestations/:attestation_id", to: "repository_attestations#show", as: :attestation, via: [:get]
    match  "attestations/:attestation_id/download", to: "repository_attestations#download_attestation", as: :download_attestation, via: [:get]
    delete  "attestations", to: "repository_attestations#destroy", as: :delete_attestations

    # FilesController
    get    "", to: "files#disambiguate", as: :repository, format: false, defaults: { format: :html }

    # Topics
    get "topic_autocomplete",         to: "topics#autocomplete",       as: :topic_autocomplete

    # Contribute to owner/repo-name
    resource :contribute_page, only: [:show], path: "contribute"

    # Opt in to view objectionable content
    post "opt_in", to: "repositories#opt_in_to_view", as: :opt_in_to_view

    # Dismiss repository content warning banner
    post "dismiss_content_warning_banner", to: "repositories#dismiss_content_warning_banner", as: :dismiss_content_warning_banner

    # Tiered Reporting routes
    post "report_content", to: "abuse_reports#create"
    get "reported_content", to: "edit_repositories#reported_content"
    get "abuse_reporters", to: "edit_repositories#abuse_reporters"
    put "toggle_tiered_reporting", to: "edit_repositories#toggle_tiered_reporting"
    put  "resolve_abuse_reports",   to: "abuse_reports#resolve_abuse_reports"
    put  "unresolve_abuse_reports", to: "abuse_reports#unresolve_abuse_reports"

    # Merge queue
    scope "queue/:merge_queue_branch", as: "merge_queue", constraints: { merge_queue_branch: /.*/ } do
      resources :queue_partial, only: [:show], module: :merge_queues
      resources :entries, only: [:index, :create, :destroy, :update], module: :merge_queues do
        resource :status, only: [:show]
      end
    end

    # no :merge_queue_branch parameter defaults to default repository branch
    get "queue", to: "merge_queues#show"
    get "queue/:merge_queue_branch", as: "merge_queue", to: "merge_queues#show", constraints: { merge_queue_branch: /.*/ }
    delete "queue/:merge_queue_branch/clear", as: "clear_merge_queue", to: "merge_queues#clear", constraints: { merge_queue_branch: /.*/ }

    # Pin/Unpin to the owner's profile
    resource :profile_pin, only: [:create, :destroy], module: :repos, as: "repository_profile_pin"
    post "pin_organization_repo", to: "repos/profile_pins#pin_organization_repo", as: :pin_organization_repo

    # Actions Metrics: Actions Usage Metrics/Actions Performance Metrics
    scope "/actions/metrics" do
      # Usage
      resource :usage, only: :show, controller: "actions_metrics/usage", as: :actions_usage_metrics_repo
      post :usage, action: :index, only: :index, controller: "actions_metrics/usage"
      post "usage/export", action: :export, only: :export, controller: "actions_metrics/usage"
      post "usage/export_status", action: :export_status, only: :export_status, controller: "actions_metrics/usage"
      get "usage/workflows", action: :workflows, only: :workflows, controller: "actions_metrics/usage"
      get "usage/jobs", action: :jobs, only: :jobs, controller: "actions_metrics/usage"
      get "usage/runner_labels", action: :runner_labels, only: :runner_labels, controller: "actions_metrics/usage"
      post "usage/summary", action: :summary, only: :summary, controller: "actions_metrics/usage"

      # Performance
      resource :performance, only: :show, controller: "actions_metrics/performance", as: :actions_performance_metrics_repo
      post :performance, action: :index, only: :index, controller: "actions_metrics/performance"
      post "performance/export", action: :export, only: :export, controller: "actions_metrics/performance"
      post "performance/export_status", action: :export_status, only: :export_status, controller: "actions_metrics/performance"
      get "performance/workflows", action: :workflows, only: :workflows, controller: "actions_metrics/performance"
      get "performance/jobs", action: :jobs, only: :jobs, controller: "actions_metrics/performance"
      get "performance/runner_labels", action: :runner_labels, only: :runner_labels, controller: "actions_metrics/performance"
      post "performance/summary", action: :summary, only: :summary, controller: "actions_metrics/performance"
    end
  end

  #
  # Attachments
  #
  get "/user-attachments/files/:id(/*path)", to: "attachments/repository_files#show", as: :repository_file, format: false
  get "/user-attachments/assets/:guid", to: "attachments/user_assets#show", as: :user_file, format: false

  #
  # Repository FormsController
  #
  get "repositories/forms/owner_items", to: "repos/forms#owner_items", as: :forms_owner_items
  get "repositories/forms/fork_owner_items", to: "repos/forms#fork_owner_items", as: :forms_fork_owner_items
  get "repositories/forms/owner_detail", to: "repos/forms#owner_detail", as: :forms_owner_detail

  get "assets/:user/:guid",                    to: "assets#show", as: :asset_file, format: false
  get "assets/storage/user/:user/files/:guid", to: "assets#show", as: :asset_alambic_file, format: false

  unless GitHub.enterprise?
    get "editor/actions/marketplace-search", to: "editor/actions#index", as: "editor_actions_search"
    get "editor/actions/marketplace/:action_id", to: "editor/actions#show", as: "editor_action"

    get "editor/codespaces/marketplace-search", to: "editor/dev_containers#index", as: "editor_dev_containers_search"
    get "editor/codespaces/:feature_id", to: "editor/dev_containers#show", as: "editor_dev_containers_show"
  end
  ##
  # Hook Deliveries, legacy path
  constraints(guid: WEBHOOK_GUID_REGEX, id: WEBHOOK_REGEX, hook_id: /\d+/) do
    get  "/hooks/:hook_id/deliveries",                     to: "hook_deliveries#index",     as: :hook_deliveries
    get  "/hooks/:hook_id/deliveries/:id",                 to: "hook_deliveries#show",      as: :hook_delivery
    get  "/hooks/:hook_id/deliveries/:id/payload.:format", to: "hook_deliveries#payload",   as: :hook_delivery_payload, format: "json"
    get  "/hooks/:hook_id/redeliveries",                     to: "hook_deliveries#redeliveries",     as: :hook_redeliveries
    post "/hooks/:hook_id/deliveries/:guid/redeliver",       to: "hook_deliveries#redeliver", as: :redeliver_hook_delivery
  end

  ##
  # Announcements
  delete "dismiss_announcement/:id", to:     "announcements/announcement#dismiss",      as: :dismiss_announcement
  delete "expand_announcement/:id", to:     "announcements/announcement#expand",      as: :expand_announcement

  ##
  # Surveys
  post "/survey-responses", controller: "survey_responses", action: "update", as: :survey_responses

  if Rails.env.test?
    match "/low_risk_sudo",    to: "sudo_test#low_risk_sudo",    via: [:get, :post, :put, :delete]
    match "/2fa_sudo",         to: "sudo_test#two_factor_sudo",  via: [:get, :post, :put, :delete]
    match "/redirect_to_back", to: "sudo_test#redirect_to_back", via: [:get, :post, :put, :delete]

    get "/render_safeguard/test/with_respond_to", to: "render_safeguard#show_with_respond_to"
    get "/render_safeguard/test/without_respond_to", to: "render_safeguard#show_without_respond_to"
  end

  resources :sparkles, only: [:destroy]

  resources :profiles, module: :profiles, only: [], id: USERID_REGEX, path: "", as: :user do
    constraints ->(request) { request.format == :atom } do
      resource :atom_feed, only: [:show], path: ""
    end

    constraints ->(request) { request.format == :png } do
      resource :avatar, only: [:show], path: ""
    end

    constraints ->(request) { request.format == :keys } do
      resource :ssh_key, only: [:show], path: ""
    end

    constraints ->(request) { request.format == :gpg } do
      resource :gpg_key, only: [:show], path: ""
    end

    constraints ->(request) { request.format == :sigkeys } do
      resource :ssh_signing_key, only: [:show], path: ""
    end

    constraints ->(request) { request.query_parameters[:tab] == "following" } do
      resources :following, only: [:index], path: ""
    end

    constraints ->(request) { request.query_parameters[:tab] == "followers" } do
      resources :followers, only: [:index], path: ""
    end

    constraints ->(request) { request.query_parameters[:tab] == "packages" } do
      resources :packages, only: [:index], path: ""
    end

    constraints ->(request) { request.query_parameters[:tab] == "projects" } do
      resources :projects, only: [:index], path: ""
    end

    constraints ->(request) { request.query_parameters[:tab] == "repositories" } do
      resources :repositories, only: [:index], path: ""
    end

    constraints ->(request) {
      request.xhr? &&
      request.query_parameters[:tab] == "stars" &&
      request.query_parameters[:user_lists_sort].present?
    } do
      resources :lists, only: [:index], path: "", controller: "user_lists"
    end

    constraints ->(request) { request.query_parameters[:tab] == "stars" } do
      resources :stars, only: [:index], path: ""
    end

    constraints ->(request) { request.query_parameters[:tab] == "achievements" } do
      resources :achievements, only: [:index], path: ""
    end

    constraints ->(request) { request.xhr? && request.query_parameters[:tab] == "contributions" } do
      resource :contribution, only: [:show], path: ""
    end
  end

  resources :orgs, module: :orgs, only: [], id: USERID_REGEX, path: "" do
    constraints ->(request) { request.query_parameters[:tab] == "members" } do
      resources :people, only: [:index], path: ""
    end
  end

  resources :profiles, only: [:show], param: :user_id, user_id: USERID_REGEX, path: "", as: :user

  get "/ip_allowlist_checks/:owner_type/:owner_id", to: "ip_allowlist_checks#show", as: :ip_allowlist_checks

  get "/_speedscope/index.html", to: "speedscope#index"
  get "/_speedscope/*filename", to: "speedscope#file"

  scope "/_view_fragments/Voltron::CommitFragmentsController/show/:user_id/:repository/:name", controller: "voltron/commit_fragments", constraints: { repository: REPO_REGEX, user_id: USERID_REGEX } do
    get :repo_layout
    get :commit_show_header
    get :commit_show_contents
  end

  scope "/_view_fragments/Voltron::DiscussionsFragmentsController/show/orgs/:org/:discussion_number", controller: "voltron/discussions_fragments", constraints: { org: USERID_REGEX } do
    get :discussion_layout
    get :sidebar_content
    get :content_1
    get :content_2
  end

  scope "/_view_fragments/Voltron::DiscussionsFragmentsController/show/:user_id/:repository/:discussion_number", controller: "voltron/discussions_fragments", constraints: { repository: REPO_REGEX, user_id: USERID_REGEX } do
    get :discussion_layout
    get :sidebar_content
    get :content_1
    get :content_2
  end

  scope "/_view_fragments/voltron/pull_requests/show/:user_id/:repository/:id", controller: "voltron/pull_requests_fragments", constraints: { repository: REPO_REGEX, user_id: USERID_REGEX } do
    get :pull_request_layout
    get :conversation_content
    get :conversation_sidebar
  end

  scope "/_view_fragments/issues/show/:user_id/:repository/:id", controller: "voltron/issues_fragments", constraints: { repository: REPO_REGEX, user_id: USERID_REGEX } do
    get :issue_layout
    get :issue_conversation_content
    get :issue_conversation_sidebar
  end

  get "/_voltron/routes", to: "voltron/routes#show"

  get "/_react_core_examples", to: "react_core_examples#index", as: :_react_core_examples_index
  get "/_react_core_examples/layout", to: "react_core_examples#layout", as: :_react_core_examples_layout
  get "/_react_core_examples/dependent_data", to: "react_core_examples#dependent_data", as: :_react_core_examples_dependent_data
  get "/_react_core_examples/dependent_data/deferred", to: "react_core_examples#dependent_data_deferred", as: :_react_core_examples_dependent_data_deferred
  get "/_react_core_examples/enriched_data", to: "react_core_examples#enriched_data", as: :_react_core_examples_enriched_data
  get "/_react_core_examples/enriched_data/deferred", to: "react_core_examples#enriched_data_deferred", as: :_react_core_examples_enriched_data_deferred
  get "/_react_core_examples/live_data", to: "react_core_examples#live_data", as: :_react_core_examples_live_data
  get "/_react_core_examples/mutations", to: "react_core_examples#mutations", as: :_react_core_examples_mutations
  put "/_react_core_examples/mutations", to: "react_core_examples#mutations_update", as: :_react_core_examples_mutations_update
  get "/_react_core_examples/pagination", to: "react_core_examples#pagination", as: :_react_core_examples_pagination
  get "/_react_core_examples/pagination/deferred", to: "react_core_examples#pagination_deferred", as: :_react_core_examples_pagination_deferred
  get "/_react_core_examples/shared_components", to: "react_core_examples#shared_components", as: :_react_core_examples_shared_components
  get "/_react_core_examples/nested-error/render-error", to: "react_core_examples#nested_render_error", as: :_react_core_examples_nested_render_error
  get "/_react_core_examples/nested-error/loader-error", to: "react_core_examples#nested_loader_error", as: :_react_core_examples_nested_loader_error

  get "/_react_sandbox", to: "react_sandbox#index", as: :_react_sandbox_index
  post "/_react_sandbox/fetch_test", to: "react_sandbox#fetch_test", as: :_react_sandbox_fetch_test
  get "/_react_sandbox/alloy", to: "react_sandbox#alloy_show", as: :_react_sandbox_alloy_show
  get "/_react_sandbox/lazy", to: "react_sandbox#lazy", as: :_react_sandbox_lazy
  get "/_react_sandbox/ssr-error", to: "react_sandbox#ssr_error", as: :_react_sandbox_ssr_error
  get "/_react_sandbox/:sandbox_id", to: "react_sandbox#show", as: :_react_sandbox_show
  get "/_react_sandbox/:owner/:repo/issues", to: "react_sandbox#issues_index", as: :_react_sandbox_issues_index
  get "/_react_sandbox/:owner/:repo/issues/:issue_number", to: "react_sandbox#issues_show", as: :_react_sandbox_issues_show

  get "/_react_sandbox_future", to: "react_sandbox_future#index", as: :_react_sandbox_future_index
  get "/_react_sandbox_future/_layout", to: "react_sandbox_future#layout", as: :_react_sandbox_future_layout
  get "/_react_sandbox_future/client_error", to: "react_sandbox_future#client_error", as: :_react_sandbox_future_client_error
  get "/_react_sandbox_future/dashboard", to: "react_sandbox_future#dashboard", as: :_react_sandbox_future_dashboard
  get "/_react_sandbox_future/dashboard/issues", to: "react_sandbox_future#dashboard_issues", as: :_react_sandbox_future_dashboard_issues
  get "/_react_sandbox_future/dashboard/issues/deferred", to: "react_sandbox_future#dashboard_issues_deferred", as: :_react_sandbox_future_dashboard_issues_deferred
  get "/_react_sandbox_future/dashboard/pulls", to: "react_sandbox_future#dashboard_pulls", as: :_react_sandbox_future_dashboard_pulls
  get "/_react_sandbox_future/dashboard/pulls/deferred", to: "react_sandbox_future#dashboard_pulls_deferred", as: :_react_sandbox_future_dashboard_pulls_deferred
  get "/_react_sandbox_future/dashboard/deferred", to: "react_sandbox_future#dashboard_deferred", as: :_react_sandbox_future_dashboard_deferred
  get "/_react_sandbox_future/:param/deferred", to: "react_sandbox_future#deferred", as: :_react_sandbox_future_deferred
  get "/_react_sandbox_future/:param", to: "react_sandbox_future#show", as: :_react_sandbox_future_show
  get "/_react_sandbox_future/dashboard/discussions", to: "react_sandbox_future#dashboard_discussions", as: :_react_sandbox_future_dashboard_discussions


  get "/_soft_navigation_tests", to: "soft_navigation_tests#index", as: :_soft_navigation_tests_index
  get "/__soft_navigation_tests/_layout", to: "_soft_navigation_tests#layout", as: :__soft_navigation_tests_layout
  get "/_soft_navigation_tests/:param", to: "soft_navigation_tests#show", as: :_soft_navigation_tests_show
  get "/_soft_navigation_tests_other", to: "soft_navigation_tests#other_index", as: :_soft_navigation_tests_other_index
  get "/_soft_navigation_tests_other/_layout", to: "soft_navigation_tests#other_layout", as: :_soft_navigation_tests_other_layout
  get "/_soft_navigation_tests_other/:param", to: "soft_navigation_tests#other_show", as: :_soft_navigation_tests_other_show

  get "/_react_core_examples/feature_flag", to: "react_core_examples#feature_flag", as: :_react_core_examples_feature_flag

  unless GitHub.enterprise?
    get "/_vexi_sandbox", to: "vexi_sandbox#index", as: :_vexi_sandbox_index
  end

  get "/_navigation_test/rails", to: "navigation_test#rails"
  get "/_navigation_test/react/:data/:kind", to: "navigation_test#react"

  # Expose the internal graphql schema for use by frontend apps.
  get "/_graphql", to: "internal_graphql#show" # Must be GETtable for preloading
  post "/_graphql", to: "internal_graphql#create" # Mutations must flow through here for safety

  # The only way to get consistent 404 rendering in Rails 3+ is to define a
  # catch all route. This ensures that all bad routes are rendered using the
  # same `render_404` logic as other 404s in the application.
  #
  # WARNING: This route must be the last route in the routes file.
  match "*unmatched_route", to: "routing_error#index", via: [:get, :post, :put, :patch, :delete]
end
