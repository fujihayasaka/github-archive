# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Serializers
    class BusinessReconciliationJobEntityType < ActiveJob::Serializers::ObjectSerializer

      SERIALIZED_PROPERTY_KEY = "_gh_sc_business_reconciliation_job_entity_type"

      class EntityType < T::Enum
        enums do
          Organization = new
          User = new
        end
      end

      sig { override.params(argument: T.untyped).returns(T::Boolean) }
      def serialize?(argument)
        argument.is_a?(EntityType)
      end

      sig { override.params(type: EntityType).returns(T::Hash[T.untyped, T.untyped]) }
      def serialize(type)
        super({ SERIALIZED_PROPERTY_KEY => type.serialize })
      end

      sig { override.params(hash: T::Hash[T.untyped, T.untyped]).returns(EntityType) }
      def deserialize(hash)
        EntityType.deserialize(hash[SERIALIZED_PROPERTY_KEY])
      end
    end
  end
end

Rails.application.config.active_job.custom_serializers << SecurityCenter::Serializers::BusinessReconciliationJobEntityType
