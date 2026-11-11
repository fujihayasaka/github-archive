# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class DiffRange < Platform::Inputs::Base
      graphql_name "DiffRange"
      description "A range of commits which define a diff."
      visibility :internal

      argument :start_commit_oid, Scalars::GitObjectID, "The OID of the start commit for the range.", required: true

      argument :end_commit_oid, Scalars::GitObjectID, "The OID of the end commit for the range.", required: true

      argument :base_commit_oid, Scalars::GitObjectID, "The OID of the latest merge base commit for this range. Used for excluding changes from base branches.", required: false
    end
  end
end
