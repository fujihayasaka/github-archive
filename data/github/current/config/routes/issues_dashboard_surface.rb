# typed: true
# frozen_string_literal: true

T.bind(self, ActionDispatch::Routing::Mapper)

scope "/issues/dashboard", as: "issues_dashboard_surface" do
  get "/", to: "issues_dashboard_surface#index"
  get "/assigned", to: "issues_dashboard_surface#index", as: :assigned
  get "/created", to: "issues_dashboard_surface#index", as: :created
  get "/mentioned", to: "issues_dashboard_surface#index", as: :mentioned
  get "/recent", to: "issues_dashboard_surface#index", as: :recent
  get "/_content", to: "issues_dashboard_surface#content"
  get "/_layout", to: "issues_dashboard_surface#layout"
  get "/deferred", to: "issues_dashboard_surface#deferred"
  # NOTE: This catch-all route must remain after any more specific routes.
  get "/:saved_view_id", to: "issues_dashboard_surface#index"
end
