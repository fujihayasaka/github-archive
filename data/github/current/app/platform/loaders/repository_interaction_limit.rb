# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class RepositoryInteractionLimit < Platform::Loader
      def self.load(object, scope)
        self.for.load([object, scope])
      end

      def fetch(objects_with_scopes)
        objects = objects_with_scopes.map(&:first)

        repositories = objects.select { |object| object.is_a?(Repository) }
        repository_ids = repositories.map(&:id)
        owners = objects.select { |object| object.is_a?(User) }
        owner_ids = (owners.map(&:id) + repositories.map(&:owner_id)).uniq

        sql_clauses = []
        sql_params = []
        if repository_ids.any?
          sql_clauses << "(repository_id IN (?))"
          sql_params << repository_ids
        end
        if owner_ids.any?
          sql_clauses << "(repository_id IS NULL AND user_id IN (?))"
          sql_params << owner_ids
        end
        limits = ::InteractionLimit.includes(:user).on_repository.not_expired.where(sql_clauses.join(" OR "), *sql_params)

        local_limits = limits.select(&:local?).index_by(&:repository_id)
        overall_limits = limits.select(&:overall?).index_by(&:user_id)

        Hash.new do |h, object_and_scope|
          object, scope = object_and_scope

          if object.is_a?(Repository)
            if scope == :local
              h[object_and_scope] = local_limits[object.id]
            else
              h[object_and_scope] = overall_limits[object.owner_id] || local_limits[object.id]
            end
          else
            h[object_and_scope] = overall_limits[object.id]
          end
        end
      end
    end
  end
end
