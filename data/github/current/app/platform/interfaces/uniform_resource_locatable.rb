# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module UniformResourceLocatable
      include Platform::Interfaces::Base
      description "Represents a type that can be retrieved by a URL."

      field :resource_path, Scalars::URI, description: "The HTML path to this resource.", null: false

      def resource_path
        if @object.is_a?(Repository)
          @object.async_owner.then do
            @object.path
          end
        else
          @object.path
        end
      end

      field :url, Scalars::URI, description: "The URL to this resource.", null: false
    end
  end
end
