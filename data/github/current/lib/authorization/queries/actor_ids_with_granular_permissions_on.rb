# typed: true
# frozen_string_literal: true
require_relative "base_query"

module Authorization
  module Queries
    class ActorIdsWithGranularPermissionsOn < BaseQuery
      ACCEPTABLE_SUBJECT_TYPES = %w[User Organization Bot Repository ImportableRepository ProtectedBranch]
      DEFAULT_BATCH_SIZE = 1_000

      attr_reader :actor_type, :subject_type, :subject_ids, :owner_ids, :permissions, :min_action

      def initialize(actor_type:, subject_type:, subject_ids:, owner_ids: nil, permissions:, min_action: :read)
        @actor_type = actor_type
        @subject_ids = Array(subject_ids).uniq
        @owner_ids = Array(owner_ids).uniq if owner_ids
        @permissions = permissions
        @subject_type = subject_type.to_s
        @min_action = min_action
      end

      def execute_implementation
        emit_lists_sizes
        GitHub.dogstats.distribution_time("execute_in_batches.dist") do
          results = []
          query_string = <<-SQL
            SELECT actor_id
            FROM :abilities_or_permissions
            WHERE subject_id IN (:subject_ids)
            AND subject_type IN (:subject_types)
            AND actor_type = :ability_type
            AND action >= :min_action
          SQL

          router = Permissions::QueryRouter.for(subject_types: direct_permissions)
          subject_ids.each_slice(DEFAULT_BATCH_SIZE) do |batch_of_subject_ids|
            model = router.model
            bindings = {
              ability_type:  actor_type,
              subject_ids:   batch_of_subject_ids,
              subject_types: direct_permissions,
              min_action:    Ability.actions[min_action],
              abilities_or_permissions: Arel.sql(model.table_name)
            }
            results.concat(model.connection.select_rows(Arel.sql(query_string, **bindings)))
          end

          router = Permissions::QueryRouter.for(subject_types: indirect_permissions)
          Array(owner_ids).each_slice(DEFAULT_BATCH_SIZE) do |batch_of_owner_ids|
            model = router.model
            bindings = {
              ability_type:  actor_type,
              subject_ids:   batch_of_owner_ids,
              subject_types: indirect_permissions,
              min_action:    Ability.actions[min_action],
              abilities_or_permissions: Arel.sql(model.table_name)
            }
            results.concat(model.connection.select_rows(Arel.sql(query_string, **bindings)))
          end

          results.flatten.uniq
        end
      end

      private

      def default_result
        []
      end

      def direct_permissions
        if permissions == :any
          case subject_type
          when "Repository", "ImportableRepository"
            Repository::Resources.subject_types.map { |type| "#{Repository::Resources::INDIVIDUAL_ABILITY_TYPE_PREFIX}/#{type}" }
          when "Organization"
            Organization::Resources.subject_types.map { |type| "#{Organization::Resources::ABILITY_TYPE_PREFIX}/#{type}" }
          when "User", "Bot"
            User::Resources.subject_types.map { |type| "#{User::Resources::ABILITY_TYPE_PREFIX}/#{type}" }
          when "ProtectedBranch"
            ProtectedBranch::Resources.all_prefixed_subject_types
          end
        else
          permissions.map do |permission|
            direct_ability_subject_type(permission)
          end
        end
      end

      def indirect_permissions
        if permissions == :any
          return unless %w(Repository ImportableRepository).include?(subject_type)
          Repository::Resources.subject_types.map { |type| "#{Repository::Resources::ALL_ABILITY_TYPE_PREFIX}/#{type}" }
        else
          permissions.map do |perm|
            indirect_ability_subject_type(perm)
          end.uniq
        end
      end

      def direct_ability_subject_type(permission)
        case subject_type
        when "Repository", "ImportableRepository"
          "#{Repository::Resources::INDIVIDUAL_ABILITY_TYPE_PREFIX}/#{permission}"
        when "Organization"
          "#{Organization::Resources::ABILITY_TYPE_PREFIX}/#{permission}"
        when "User", "Bot"
          "#{User::Resources::ABILITY_TYPE_PREFIX}/#{permission}"
        when "ProtectedBranch"
          "#{ProtectedBranch::Resources::ABILITY_TYPE_PREFIX}/#{permission}"
        end
      end

      def indirect_ability_subject_type(permission)
        "#{Repository::Resources::ALL_ABILITY_TYPE_PREFIX}/#{permission}" if %w(Repository ImportableRepository).include?(subject_type)
      end

      def validation_errors
        errors = []

        if !actor_type
          errors << validation_error(:missing_actor_type)
        end

        if !subject_type.present?
          errors << validation_error(:missing_subject_type)
        end

        if !subject_ids.present?
          errors << validation_error(:missing_actor_ids_or_subject_ids)
        end

        if !valid_action?(min_action)
          errors << validation_error(:invalid_action, action: min_action)
        end

        if subject_type == "Organization" && owner_ids.present?
          errors << "Cannot supply owner_ids for subject_type Organization"
        end

        unless ACCEPTABLE_SUBJECT_TYPES.include?(subject_type)
          errors << validation_error(:subject_not_acceptable_class, klass: subject_type,
                                     subject_types: ACCEPTABLE_SUBJECT_TYPES)
        end

        errors
      end

      def emit_distribution_for(key, value, tags: [])
        GitHub.dogstats.distribution(stats_key(key), value, tags: tags)
      end

      def emit_lists_sizes
        emit_distribution_for("queried_subject_ids", subject_ids.count)
        emit_distribution_for("queried_owner_ids", owner_ids.count) if owner_ids.present?
      end

      def stats_key(suffix)
        "queries.actor_ids_with_granular_permissions_on.#{suffix}.dist"
      end
    end
  end
end
