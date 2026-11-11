# typed: true
# frozen_string_literal: true

module Platform
  module Edges
    class EnterpriseTeamAssignedOrganization < Edges::Base
      description "Represents an organization that an enterprise team is assigned to."

      minimum_accepted_scopes ["read:org", "read:enterprise"]

      field :node, Objects::Organization, null: true
    end
  end
end
