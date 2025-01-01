# typed: strict
# frozen_string_literal: true

require "monolith-twirp-actionsresults-core"

module ActionsResults
  module Twirp
    class PoliciesClient < ActionsResults::Twirp::BaseClient
      sig do
        params(
          entity_type: Integer,
          entity_id: Integer,
          storage_limit: Integer,
          actor_id: String,
        ).returns(T.nilable(T::Boolean))
      end
      def upsert_cache_storage_policy(entity_type:, entity_id:, storage_limit:, actor_id:)
        response = rpc(
          :UpsertCacheStoragePolicy,
          entity_type: entity_type,
          entity_id: entity_id,
          storage_limit:,
          actor_id:,
        )

        return nil unless response.call_succeeded?
        response.value&.ok
      end

      sig do
        params(
          policy_entities: T::Array[{ entity_type: Integer, entity_id: Integer }],
        ).returns(T.nilable(T::Array[{ entity_type: Integer, entity_id: Integer, storage_limit: T.nilable(Integer) }]))
      end
      def get_cache_storage_policy(policy_entities:)
        response = rpc(
          :GetCacheStoragePolicy,
          policy_entities: policy_entities,
        )

        return nil unless response.call_succeeded?

        response_entities = response.value&.policy_entities || []
        policy_entities.map do |entity|
          expected_entity_type = policy_entity_type_symbol_from_integer(entity[:entity_type])

          response_entity = response_entities.find do |re|
            re.entity_type == expected_entity_type && re.entity_id == entity[:entity_id]
          end
          {
            entity_type: entity[:entity_type],
            entity_id: entity[:entity_id],
            storage_limit: response_entity&.storage_limit
          }
        end
      end

      sig do
        params(
          entity_type: Integer,
          entity_id: Integer,
          actor_id: String,
        ).returns(T.nilable(T::Boolean))
      end
      def delete_cache_storage_policy(entity_type:, entity_id:, actor_id:)
        response = rpc(
          :DeleteCacheStoragePolicy,
          entity_type: entity_type,
          entity_id: entity_id,
          actor_id:,
        )

        return nil unless response.call_succeeded?

        response.value&.ok
      end

      sig do
        params(
          entity_type: Integer,
          entity_id: Integer,
          retain_for: Integer,
          actor_id: String,
        ).returns(T.nilable(T::Boolean))
      end
      def upsert_cache_retention_policy(entity_type:, entity_id:, retain_for:, actor_id:)
        response = rpc(
          :UpsertCacheRetentionPolicy,
          entity_type: entity_type,
          entity_id: entity_id,
          retain_for:,
          actor_id:,
        )

        return nil unless response.call_succeeded?

        response.value&.ok
      end

      sig do
        params(
          policy_entities: T::Array[{ entity_type: Integer, entity_id: Integer }],
        ).returns(T.nilable(T::Array[{ entity_type: Integer, entity_id: Integer, retain_for: T.nilable(Integer) }]))
      end
      def get_cache_retention_policy(policy_entities:)
        converted_entities = policy_entities.map do |entity|
          {
            entity_type: entity[:entity_type],
            entity_id: entity[:entity_id],
          }
        end

        response = rpc(
          :GetCacheRetentionPolicy,
          policy_entities: converted_entities,
        )

        return nil unless response.call_succeeded?

        response_entities = response.value&.policy_entities || []
        policy_entities.map do |entity|
          expected_entity_type = policy_entity_type_symbol_from_integer(entity[:entity_type])

          response_entity = response_entities.find do |re|
            re.entity_type == expected_entity_type && re.entity_id == entity[:entity_id]
          end
          {
            entity_type: entity[:entity_type],
            entity_id: entity[:entity_id],
            retain_for: response_entity&.retain_for
          }
        end
      end

      sig do
        params(
          entity_type: Integer,
          entity_id: Integer,
          actor_id: String,
        ).returns(T.nilable(T::Boolean))
      end
      def delete_cache_retention_policy(entity_type:, entity_id:, actor_id:)
        response = rpc(
          :DeleteCacheRetentionPolicy,
          entity_type: entity_type,
          entity_id: entity_id,
          actor_id:,
        )

        return nil unless response.call_succeeded?

        response.value&.ok
      end

      sig { params(entity_type: Integer).returns(Symbol) }
      def policy_entity_type_symbol_from_integer(entity_type)
        case entity_type
        when MonolithTwirp::ActionsResults::Core::V1::PolicyEntityType::POLICY_ENTITY_TYPE_REPOSITORY
          :POLICY_ENTITY_TYPE_REPOSITORY
        when MonolithTwirp::ActionsResults::Core::V1::PolicyEntityType::POLICY_ENTITY_TYPE_ORGANIZATION
          :POLICY_ENTITY_TYPE_ORGANIZATION
        when MonolithTwirp::ActionsResults::Core::V1::PolicyEntityType::POLICY_ENTITY_TYPE_BUSINESS
          :POLICY_ENTITY_TYPE_BUSINESS
        else
          raise ArgumentError, "Unknown entity type: #{entity_type}"
        end
      end

      private

      sig { returns(T.class_of(::Twirp::Client)) }
      def twirp_class
        ::MonolithTwirp::ActionsResults::Core::V1::PoliciesAPIClient
      end
    end
  end
end
