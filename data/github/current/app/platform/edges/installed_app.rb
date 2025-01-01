# typed: true
# frozen_string_literal: true

module Platform
  module Edges
    class InstalledApp < Edges::Base
      node_type Objects::App
      description "An installation on a repository"
      visibility :internal

      # Since the node is _not_ `object.node`,
      # override this to pass something else.
      def self.authorized?(object, context)
        object.node.async_integration.then do |integration|
          node_type.authorized?(integration, context)
        end
      end

      def node
        object.node.async_integration
      end
    end
  end
end
