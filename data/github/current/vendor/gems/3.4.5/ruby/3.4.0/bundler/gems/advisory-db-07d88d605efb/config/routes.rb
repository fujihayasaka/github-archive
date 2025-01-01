# frozen_string_literal: true

Rails.application.routes.draw do
  root "homepage#show"

  get "/ping", to: proc { [200, {}, ["OK"]] }

  get "/_chatops" => "chatops#list"
  post "/_chatops/:chatop" => "chatops#execute_chatop"

  get "/markdown-preview" => "markdown#preview"

  post "/webhook" => "webhooks#create"

  get "/search" => "inbox#search"
  post "/set_color_mode" => "inbox#set_color_mode"

  resources :epss, only: [:show], param: :ghsa_id

  resource :dependency_graph, controller: "dependency_graph", only: [] do
    collection do
      get :package_repo
      get :estimated_impact
    end
  end

  resource :ecosystem_registries, controller: "ecosystem_registries", only: [] do
    collection do
      get :package_link
    end
  end

  get "/cves", to: "cves#index"
  post "/cves", to: "cves#create"

  resources :cwes, only: [:index]

  resources :blocklisted_terms, except: [:edit, :update]

  resources :labels

  resources :advisory_reviews, except: [:edit, :destroy], param: :ghsa_id do
    member do
      get :timeline
      get :diff
      put :close
      put :reopen
      put :publish
      put :withdraw
      put :revert
      put :approve
      put :set_labels
    end
  end

  post "advisory_reviews/bulk_close", to: "advisory_reviews_bulk_operations#bulk_close"
  post "advisory_reviews/bulk_assignment", to: "advisory_reviews_bulk_operations#bulk_assignment"
  post "advisory_reviews/bulk_ecosystem_and_package_name", to: "advisory_reviews_bulk_operations#bulk_ecosystem_and_package_name"
  post "advisory_reviews/bulk_label_options", to: "advisory_reviews_bulk_operations#bulk_label_options"
  post "advisory_reviews/bulk_labels", to: "advisory_reviews_bulk_operations#bulk_labels"

  resources :campaigns, except: [:edit, :update]

  resources :advisory_review_approvals, only: [:create, :update]

  resources :cve_review_triage, only: [:index, :show], param: :ghsa_id, path: "cve_reviews/triage" do
    collection do
      get :done
    end

    member do
      put :open
      put :close
      put :skip
    end
  end

  resources :cve_reviews, only: [:index, :create, :new, :show, :update], param: :ghsa_id do
    member do
      get :timeline
      put :publish
      put :reject
      put :reopen
    end
  end

  resources :validations do
    collection do
      post :cve_id
      post :replaced_by_cve_id
    end
  end

  get ":search_query", to: "inbox#search", constraints: { search_query: /(GHSA|CVE)-.+/ }
end
