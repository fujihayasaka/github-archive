# typed: strict
# frozen_string_literal: true

# Organization licensing routes - included as part main routes scoped for organizations
T.bind(self, ActionDispatch::Routing::Mapper)

if GitHub.billing_enabled?
  get "consumed_licenses", to: "consumed_licenses#show", as: :consumed_licenses
end

get "settings/licensing", to: "settings/licensing#index", as: :settings_licensing_index
