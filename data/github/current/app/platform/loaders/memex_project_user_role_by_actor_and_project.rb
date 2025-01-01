# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class MemexProjectUserRoleByActorAndProject < Platform::Loader

      class ActorType < T::Enum
        enums do
          Team = new
          User = new
        end
      end

      sig do
        params(
          project_id: T.nilable(Integer),
          actor_id: T.nilable(Integer),
          actor_type: T.nilable(T.any(ActorType::Team, ActorType::User))
        ).returns(Promise[T::Array[UserRole]])
      end
      def self.load(project_id: nil, actor_id: nil, actor_type: nil)
        if project_id.nil? && actor_id.nil?
          raise Errors::Internal.new("At least one `project_id` or `actor_id` should be provided.")
        end

        actor_type = actor_type.serialize.capitalize if actor_type.present?

        self.for.load(project_id: project_id, actor_id: actor_id, actor_type: actor_type)
      end

      sig do
        params(
          entries: T::Array[
            T::Hash[Symbol, T.any(String, Integer)]
          ]
        ).returns(
          T::Hash[T::Array[Integer], T::Array[UserRole]]
        )
      end
      def fetch(entries)
        query = ::UserRole.where(target_type: "MemexProject").and(
          entries.each_with_index.reduce(UserRole.all) do |accu, (entry, index)|
            hash = entry.dup
            hash[:target_id] = T.must(hash.delete :project_id) if hash[:project_id].present?
            index == 0 ? accu.where(**hash.compact) : accu.or(UserRole.where(**hash.compact))
          end
        )

        entries.each_with_object(Hash.new { [] }) do |entry, hash|
          project_id = entry[:project_id]
          actor_id = entry[:actor_id]

          hash[entry] = query.filter do |role|
            if project_id.present?
              role.target_id == project_id && (
                actor_id.present? ? role.actor_id == actor_id : true
            )
            else
              role.actor_id == actor_id
            end
          end
        end
      end
    end
  end
end
