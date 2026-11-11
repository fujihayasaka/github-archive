# typed: true
# frozen_string_literal: true

T.bind(self, ActionDispatch::Routing::Mapper)

scope "/pulls", module: :dashboard_surface, as: "dashboard_surface" do
  get "/_layout", to: "layout"
  get "/deferred", to: "deferred"
end

put "/pulls/preferences", to: "dashboard_surface_preferences#update", as: :dashboard_surface_update_preferences
