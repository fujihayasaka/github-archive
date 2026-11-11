# typed: strict
# frozen_string_literal: true

# Orgs licensing routes - included as part main routes scoped for orgs
T.bind(self, ActionDispatch::Routing::Mapper)

get "/invitations/licensing_details", to: "orgs/invitations_licensing_details#show", as: :org_invitations_licensing_details
resource :licensing_headroom, only: :show, controller: "orgs/licensing_headroom", as: :org_licensing_headroom
