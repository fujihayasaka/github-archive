# frozen_string_literal: true

module HydroHandlers
  module GitHub
    class UserSerializer < ActiveJob::Serializers::ObjectSerializer
      def serialize?(argument)
        argument.is_a?(::HydroHandlers::GitHub::User)
      end

      def serialize(user)
        super(
          attributes: user.attributes,
          installation_id: user.installation_id
        )
      end

      def deserialize(hash)
        hash = hash.with_indifferent_access
        ::HydroHandlers::GitHub::User.new(hash.fetch(:attributes), installation_id: hash.fetch(:installation_id))
      end
    end
  end
end
