# typed: true
# frozen_string_literal: true

module CommandPalette
  module Actions
    class AccessPolicyAction < CommandPalette::Action
      TYPE = :access_policy
      DESCRIPTION = "Access Policy"

      def initialize(path:)
        super(type: TYPE, description: DESCRIPTION, path: path)
      end
    end
  end
end
