# frozen_string_literal: true

module HydroHandlers
  module GitHub
    class RepositorySerializer < ActiveJob::Serializers::ObjectSerializer
      def serialize?(argument)
        argument.is_a?(::HydroHandlers::GitHub::Repository)
      end

      def serialize(repo)
        super(
          attributes: repo.raw_attributes,
          owner: ::HydroHandlers::GitHub::UserSerializer.serialize(repo.owner)
        )
      end

      def deserialize(hash)
        hash = hash.with_indifferent_access
        owner = ::HydroHandlers::GitHub::UserSerializer.deserialize(hash.fetch(:owner))
        ::HydroHandlers::GitHub::Repository.new(hash.fetch(:attributes), owner: owner)
      end
    end
  end
end
