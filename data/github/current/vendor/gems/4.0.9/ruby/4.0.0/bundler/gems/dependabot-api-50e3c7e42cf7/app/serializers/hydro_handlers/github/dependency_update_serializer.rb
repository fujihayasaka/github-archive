# frozen_string_literal: true

module HydroHandlers
  module GitHub
    class DependencyUpdateSerializer < ActiveJob::Serializers::ObjectSerializer
      def serialize?(argument)
        argument.is_a?(::HydroHandlers::GitHub::DependencyUpdate)
      end

      def serialize(dependency_update)
        super(
          attributes: dependency_update.attributes
        )
      end

      def deserialize(hash)
        attributes = hash.with_indifferent_access.fetch(:attributes)
        ::HydroHandlers::GitHub::DependencyUpdate.new(attributes)
      end
    end
  end
end
