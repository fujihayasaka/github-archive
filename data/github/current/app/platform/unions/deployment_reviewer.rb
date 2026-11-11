# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class DeploymentReviewer < Platform::Unions::Base
      docs_category :deployments
      description "Users and teams."

      possible_types(
        Objects::User,
        Objects::Team,
      )

      # BusinessTeam is a subclass of Team that represents enterprise-level teams.
      # It doesn't have its own Platform type, so we resolve it as Team.
      def self.resolve_type(object, context)
        if object.is_a?(::BusinessTeam)
          Objects::Team
        else
          type_name = Platform::Helpers::NodeIdentification.type_name_from_object(object)
          Platform::Schema.get_type(type_name) || raise(Platform::Errors::Type, "Platform type '#{object.class}' is not defined.")
        end
      end
    end
  end
end
