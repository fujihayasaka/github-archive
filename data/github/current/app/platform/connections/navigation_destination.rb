# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/EnsureConsistentConnections

module Platform
  module Connections
    class NavigationDestination < Connections::Base
      description "A list of navigation destinations"
      visibility :internal

      def nodes
        @object.nodes.map(&:destination)
      end
    end
  end
end
