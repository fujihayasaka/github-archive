# typed: true
# frozen_string_literal: true

T.bind(self, ActionDispatch::Routing::Mapper)

scope "/pulls/inbox", as: "dashboard_surface_inbox" do
  get "/", to: "dashboard_surface_inbox#index"
  get "/queries", to: "dashboard_surface_inbox#queries"
  get "/deferred", to: "dashboard_surface_inbox#deferred"
end
