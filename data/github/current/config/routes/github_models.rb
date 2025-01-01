# typed: strict
# frozen_string_literal: true

T.bind(self, ActionDispatch::Routing::Mapper)

get    "/models",                                                 to: redirect("/marketplace/models"),           as: :models
get    "/marketplace/models",                                     to: "github_models/model_playgrounds#index",    as: :marketplace_models
get    "/marketplace/models/catalog",                             to: redirect("/marketplace?type=models"),       as: :marketplace_models_catalog

namespace :github_models, path: :models do
  resources :attachments, only: [:show], param: :guid
end

scope(
  "/organizations/:organization_id/settings",
  constraints: { organization_id: USERID_REGEX },
  as: :organization_settings,
) do
  namespace :github_models, path: :models, as: :models do
    resource :organization_access_policy, only: [:show, :create, :destroy], path: "access-policy", as: :access_policy
    resource :organization_billing, only: [:create], path: "billing", as: :billing
  end
end

scope(
  "/:user_id/:repository/settings",
  constraints: { repository: REPO_REGEX, user_id: USERID_REGEX },
  as: :repository_settings,
) do
  namespace :github_models, path: :models, as: :models do
    resource :repository_access_policy, only: [:show, :create, :destroy], path: "access-policy", as: :access_policy
  end
end

## Models waitlist signup
get   "/marketplace/models/waitlist",                             to: redirect("/marketplace/models")

post   "/marketplace/models/token",                               to: "github_models/token#create",              as: :create_playground_token
get    "/marketplace/models/:registry/:model",                    to: "github_models/details#show",              as: :marketplace_model
get    "/marketplace/models/:registry/:model/playground",         to: "github_models/model_playgrounds#show",    as: :marketplace_model_playground
get    "/marketplace/models/:registry/:model/playground/code",    to: "github_models/model_playgrounds#show",    as: :marketplace_model_playground_code
get    "/marketplace/models/:registry/:model/playground/json",    to: "github_models/model_playgrounds#show",    as: :marketplace_model_playground_json

get    "/marketplace/models/:registry/:model/prompt",             to: "github_models/model_playgrounds#show",    as: :marketplace_model_prompt
get    "/marketplace/models/:registry/:model/evals",              to: "github_models/model_playgrounds#show",    as: :marketplace_model_evals
get    "/marketplace/models/:registry/:model/details",            to: "github_models/details#show",              as: :marketplace_model_details

post   "/marketplace/models/:registry/:model/feedback",           to: "github_models/feedback#create",          as: :marketplace_model_feedback

## Models playground presets
get    "/marketplace/models/presets",                             to: "github_models/presets#index",            as: :marketplace_models_presets
post   "/marketplace/models/presets",                             to: "github_models/presets#create",           as: :create_models_preset
put    "/marketplace/models/presets/:url_identifier",             to: "github_models/presets#update",           as: :update_models_preset
delete "/marketplace/models/presets/:url_identifier",             to: "github_models/presets#destroy",          as: :delete_models_preset

## Models documentation
get    "/marketplace/models/:registry/:model/docs",              to: "github_models/documentation#show",        as: :marketplace_model_documentation

## Repo-scoped GitHub Models routes
scope "/:user_id/:repository", constraints: { user_id: USERID_REGEX, repository: REPO_REGEX } do
  get "models",                                    to: "github_models/repository_models#index",       as: :repo_models

  get "models/prompts",                            to: "github_models/repository_prompts#index",      as: :repo_models_prompt
  get "models/prompt/new",                         to: "github_models/repository_prompts#new",        as: :repo_models_prompt_new, format: false, defaults: { format: :html }
  get "models/prompt/edit/*name(/*path)",          to: "github_models/repository_prompts#show",       as: :models_prompt, name: /(.|\n)+/, format: false, defaults: { format: :html }
  get "models/prompt/compare/*name(/*path)",       to: "github_models/repository_prompt_comparisons#show", as: :models_prompt_compare, name: /(.|\n)+/, format: false, defaults: { format: :html }

  get "models/prompt/pull/:pull_number(/*path)",   to: "github_models/pull_request_prompts#show",       as: :repo_models_prompt_pull, pr_id: /\d+/, format: false, defaults: { format: :html }

  get "models/comparisons",                        to: "github_models/repository_prompt_comparisons#index", as: :repo_models_comparisons

  get "models/playground",                         to: "github_models/repository_playground#index",   as: :repo_models_playground

  get "models/:registry/:model/playground",        to: "github_models/repository_playground#show",    as: :models_playground
  get "models/:registry/:model",                   to: "github_models/repository_models#show",        as: :repo_model, defaults: { format: :json }
end

## CUA
get "/models/cua",          to: "github_models/cua_experience#index", as: :models_cua
get "/models/cua/session",  to: "github_models/cua_experience#index", as: :models_cua_session

get "/models/catalog", to: "github_models/catalog#index", format: :json, as: :models_catalog

if GitHub.billing_enabled?
  post "/:user_id/models/billing_enablement", to: "github_models/users/billing_enablement#create", as: :models_user_billing_enablement
  delete "/:user_id/models/billing_enablement", to: "github_models/users/billing_enablement#destroy", as: :delete_models_user_billing_enablement
end
