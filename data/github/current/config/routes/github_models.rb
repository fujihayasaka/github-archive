# typed: strict
# frozen_string_literal: true

T.bind(self, ActionDispatch::Routing::Mapper)

get    "/models",                                                 to: redirect("/marketplace/models"),           as: :models
get    "/marketplace/models",                                     to: "marketplace/model_playgrounds#index",     as: :marketplace_models
get    "/marketplace/models/catalog",                             to: redirect("/marketplace?type=models")

namespace :github_models, path: :models do
  resources :attachments, only: [:show]
end

scope(
  "/organizations/:organization_id/settings",
  constraints: { organization_id: USERID_REGEX },
  as: :organization_settings,
) do
  namespace :github_models, path: :models, as: :models do
    resource :organization_access_policy, only: [:show, :create, :destroy], path: "access-policy", as: :access_policy
  end
end

## Models waitlist signup
get   "/marketplace/models/waitlist",                             to: redirect("/marketplace/models")

post   "/marketplace/models/token",                               to: "marketplace/models/token#create",         as: :create_playground_token
get    "/marketplace/models/:registry/:model",                    to: "marketplace/models#show",                 as: :marketplace_model
get    "/marketplace/models/:registry/:model/playground",         to: "marketplace/model_playgrounds#show",      as: :marketplace_model_playground
get    "/marketplace/models/:registry/:model/playground/code",    to: "marketplace/model_playgrounds#show",      as: :marketplace_model_playground_code
get    "/marketplace/models/:registry/:model/playground/json",    to: "marketplace/model_playgrounds#show",      as: :marketplace_model_playground_json

get    "/marketplace/models/:registry/:model/prompt",             to: "marketplace/model_playgrounds#show",      as: :marketplace_model_prompt
get    "/marketplace/models/:registry/:model/evals",              to: "marketplace/model_playgrounds#show",      as: :marketplace_model_evals
get    "/marketplace/models/:registry/:model/details",            to: "marketplace/models#show",                 as: :marketplace_model_details

post   "/marketplace/models/:registry/:model/feedback",           to: "github_models/feedback#create",           as: :marketplace_model_feedback

## Models playground presets
get    "/marketplace/models/presets",                             to: "marketplace/models/presets#index",        as: :marketplace_models_presets
post   "/marketplace/models/presets",                             to: "marketplace/models/presets#create",       as: :create_models_preset
put    "/marketplace/models/presets/:url_identifier",             to: "marketplace/models/presets#update",       as: :update_models_preset
delete "/marketplace/models/presets/:url_identifier",             to: "marketplace/models/presets#destroy",      as: :delete_models_preset

## Models documentation
get    "/marketplace/models/:registry/:model/docs",              to: "github_models/documentation#show",         as: :marketplace_model_documentation

## Repo-scoped GitHub Models routes
scope "/:user_id/:repository", constraints: { user_id: USERID_REGEX, repository: REPO_REGEX } do
  get "models",                               to: "github_models/repository_models#index",       as: :repo_models

  get "models/prompts",                       to: "github_models/repository_prompts#index",      as: :repo_models_prompt
  get "models/prompt/new",                    to: "github_models/repository_prompts#new",        as: :repo_models_prompt_new, format: false, defaults: { format: :html }
  get "models/prompt/edit/*name(/*path)",     to: "github_models/repository_prompts#show",       as: :models_prompt, name: /(.|\n)+/, format: false, defaults: { format: :html }
  get "models/prompt/compare/*name(/*path)",  to: "github_models/repository_prompts#compare",    as: :models_prompt_compare, name: /(.|\n)+/, format: false, defaults: { format: :html }
end

## CUA
get "/models/cua",          to: "github_models/cua_experience#index", as: :models_cua
get "/models/cua/session",  to: "github_models/cua_experience#index", as: :models_cua_session
