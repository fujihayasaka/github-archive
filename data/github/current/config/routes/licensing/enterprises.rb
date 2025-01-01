# typed: strict
# frozen_string_literal: true

# Enterprise licensing routes - included as part of the `enterprises` routes
T.bind(self, ActionDispatch::Routing::Mapper)

resources :license_counts,
  as: :enterprise_license_counts,
  controller: "businesses/license_counts",
  param: :metric,
  only: %i(show)

resource :available_licenses,
  as: :enterprise_available_licenses,
  controller: "businesses/available_licenses",
  only: %i(show)

scope :settings do
  if GitHub.licensed_mode?
    get "license", to: "businesses/licenses#index", as: :settings_license
    get "license/download", to: "businesses/licenses#download", as: :settings_license_download
    post "license/manual_sync", to: "businesses/licenses#manual_sync", as: :settings_license_manual_sync
  end
end

if !GitHub.single_business_environment?
  resources :server_licenses, only: :show, module: :businesses, constraints: { id: /[\da-f]{6}(?:[\da-f]{14})?/ }

  resources :metered_server_licenses, only: [:show, :create], module: :businesses, constraints: { id: /[\da-f]{6}(?:[\da-f]{14})?/ }

  resource :enterprise_licensing, only: :show, controller: "businesses/enterprise_licensing" do
    member do
      get "download_consumed_licenses"
      get "download_active_committers"
      get "download_maximum_committers"

      # Enterprise Licensing survey
      delete "settings/survey", action: :destroy, as: :dismiss_enterprise_licensing_survey

      put "cancel_licensing_model_transition"
    end
  end

  scope :enterprise_licensing, controller: "businesses/bundled_license_assignments" do
    get "bundled_license_assignments/search", action: :search
    post "bundled_license_assignments", action: :create
    put "bundled_license_assignments/:id", action: :update
    delete "bundled_license_assignments/:id", action: :destroy
  end

  scope :enterprise_licensing, controller: "businesses/ghec_licensing_settings" do
    resource :ghec, controller: "businesses/ghec_licensing_settings", only: [:show] do
      get "history", action: :history, as: :ghec_licensing_settings_history
      get "licensees", action: :licensees, as: :ghec_licensing_settings_licensees
      get "summary", action: :summary, as: :ghec_licensing_settings_summary
    end
  end

  scope :enterprise_licensing, controller: "businesses/copilot_licensing" do
    get "copilot", action: :index, as: :copilot_licensing
  end

  scope :enterprise_licensing, controller: "businesses/copilot_licensing_user_assignment" do
    get "user_licenses", action: :index, as: :user_licenses
    post "assign_user_licenses", action: :create, as: :assign_user_licenses
    delete "unassign_user_licenses", action: :destroy, as: :unassign_user_licenses
  end

  scope :enterprise_licensing, controller: "businesses/copilot_licensing_organization_assignment" do
    get "organization_licenses", action: :index, as: :organization_licenses
  end

  scope :enterprise_licensing, controller: "businesses/copilot_licensing_business_team_assignment" do
    get "enterprise_team_licenses", action: :index
    post "enterprise_team_licenses", action: :create
    delete "enterprise_team_licenses", action: :destroy
  end

  scope :enterprise_licensing, controller: "businesses/copilot/standalone_enterprise_seat_management" do
    get "copilot/members/search", action: :search, as: :enterprise_members_search
    get "copilot/seat_management", action: :index, as: :team_seats
    post "copilot/seat_management", action: :create, as: :create_team_seats
    delete "copilot/seat_management", action: :destroy, as: :destroy_team_seats
    post "copilot/seat_management/download_usage", action: :download_usage, as: :download_usage
    post "copilot/seat_management/download_activity", action: :download_activity, as: :download_activity
  end
end
