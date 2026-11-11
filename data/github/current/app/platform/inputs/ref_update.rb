# typed: strict
# frozen_string_literal: true

module Platform
  module Inputs
    class RefUpdate < Platform::Inputs::Base
      description "A ref update"

      argument :name, Scalars::GitRefname, "The fully qualified name of the ref to be update. For example `refs/heads/branch-name`", required: true
      argument :after_oid, Scalars::GitObjectID, "The value this ref should be updated to.", required: true

      argument :before_oid, Scalars::GitObjectID, "The value this ref needs to point to before the update.", required: false
      argument :force, Boolean, "Force a non fast-forward update.", required: false, default_value: false
    end
  end
end
