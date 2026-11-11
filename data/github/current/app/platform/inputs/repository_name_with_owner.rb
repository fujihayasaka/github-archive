# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class RepositoryNameWithOwner < Platform::Inputs::Base
      description "A repository owner and name string as seperate fields."
      required_capabilities [:mobile_only_schema_mask]

      argument :owner, String, "The login field of a user or organization.", required: true
      argument :name, String, "The name of the repository.", required: true
    end
  end
end
