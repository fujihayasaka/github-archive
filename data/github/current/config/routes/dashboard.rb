# typed: true
# frozen_string_literal: true

T.bind(self, ActionDispatch::Routing::Mapper)

put "/dashboard/preferences", to: "dashboard/preferences#update", as: :update_dashboard_preferences
