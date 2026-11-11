# typed: true
# frozen_string_literal: true

module Platform
  module Edges
    class EnterpriseTeamMember < Edges::Base
      description "Represents a user who is a member of an enterprise team."

      minimum_accepted_scopes ["read:org", "read:enterprise"]

      field :node, Objects::User, null: true
    end
  end
end
