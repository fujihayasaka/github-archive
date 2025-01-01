# typed: strict
# frozen_string_literal: true

T.bind(self, ActionDispatch::Routing::Mapper)

get "/settings/billing/download_active_committers", to: "businesses/enterprise_licensing#download_active_committers", as: :settings_download_active_committers
get "/settings/billing/download_maximum_committers", to: "businesses/enterprise_licensing#download_maximum_committers", as: :settings_download_maximum_committers
