# typed: true
# frozen_string_literal: true

T.bind(self, ActionDispatch::Routing::Mapper)

##
# DevTools
#
# DevTools are used by the product and engineering teams to build GitHub, and
# DevTools routes are not available to Enterprise site admins. If Enterprise
# site admins will need a feature, consider adding it to Stafftools.

get "devtools", to: "devtools#index"
namespace :devtools do
  get "restricted"

  if GitHub.devtools_feature_flags_ui_enabled?
    get "feature_flags/user_autocomplete", to: "feature_flags#user_autocomplete", as: :feature_flags_user_autocomplete
    post "feature_flags/reset_timestamp", to: "feature_flags#reset_timestamp", as: :reset_timestamp
  end

  # Experiments can have dots in their params. Rails uses dots to determine
  # the format to render, but in this case we want to include dots in the
  # id, so we allow them and ignore the format segment of the param.
  resources :experiments, id: /[^\/]+/ do
    resources :mismatches, only: [:index, :show]
    resources :samples, only: [:index]
    member do
      patch :update_sample
      patch :disable_sample
      patch :clear
    end
  end

  if GitHub.devtools_feature_flags_ui_enabled?
    resources :feature_flags, except: [:edit, :update] do
      collection do
        get :service_index, to: redirect("/devtools/feature_flags")
        get :rollout, to: redirect("/devtools/feature_flags")
      end
      post :enable
      post :disable
      post :custom_gates, to: "feature_flags#activate_custom_gate", as: :custom_gate
      delete "/custom_gates/:custom_gate", to: "feature_flags#deactivate_custom_gate", as: :delete_custom_gate
      get "/actors/new", to: "feature_flags#add_actor", as: :add_actor
      get "/actors/remove", to: "feature_flags#remove_actor", as: :remove_actor
      get "/actors/check", to: "feature_flags#check_actor", as: :check_actor
      post "/actors/verify", to: "feature_flags#verify_actor", as: :verify_actor
      post :actors, to: "feature_flags#activate_actor", as: :actor
      delete :actors, to: "feature_flags#deactivate_actor", as: :delete_actor
      put "/percentage_of_actors", to: "feature_flags#update_percentage_of_actors", as: :percentage_of_actors
      put "/percentage_of_calls", to: "feature_flags#update_percentage_of_calls", as: :percentage_of_calls
    end
  end
  resources :integration_features, except: [:destroy, :show]

  resources :stream_processors, only: [:index], param: :group_id do
    put :pause, to: "stream_processors#pause"
    put :resume, to: "stream_processors#resume"
  end

  resources :toggleable_features do
    post :publish
    post :unpublish
  end

  get "datadog_metric", to: "datadog_metric#index"
  post "datadog_metric", to: "datadog_metric#generate_datadog_metric"

  get "spamurai", to: "spamurai#dashboard"

  get "/surveys", to: "surveys#index"
  get "/surveys/:slug", to: "surveys#show", slug: /[^\/.?]+/, as: :survey
  get "/surveys/:slug/batch", to: "surveys#batch", slug: /[^\/.?]+/, as: :survey_batch
end

scope path: "/devtools" do
  resource :spamurai, controller: "devtools/spamurai", format: false, only: [] do

    resources :patterns, controller: "devtools/spamurai/patterns", only: [:index, :new, :create, :show, :update, :destroy] do
      member do
        post :disable
        post :enable
      end
      collection do
        get :queues
        post :add_queue_pattern
        delete :remove_queue_pattern
      end
    end

    resources :datasources, controller: "devtools/spamurai/datasources",
                        only: [:index, :show]
  end

  # These aren't in the root-level namespace, so we can use "apps" instead of "github-apps" even in Enterprise
end

# legacy URL redirects
legacy_admin_sections = /backscatter|growth|hounds|interaction|surveys/
scope controller: "devtools", action: "bounce", format: false do
  get "admin/:section/*args", section: legacy_admin_sections
  get "stafftools/:section/*args", section: /experiments|spamurai/
  get "stafftools/science/*args", section: "experiments"
end
