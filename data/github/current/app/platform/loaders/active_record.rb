# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class ActiveRecord < Platform::Loader
      sig do
        type_parameters(:U)
        .params(
          model: T.any(::ActiveRecord::Relation, T::Class[T.all(T.type_parameter(:U), ::ActiveRecord::Base)]),
          id: T.untyped,
          column: Symbol,
          security_violation_behaviour: Symbol,
          security_unavailable_behavior: Symbol,
          case_sensitive: T::Boolean,
          shard_key: T.nilable(T::Hash[T.any(Symbol, String), Integer]),
        ).returns(Promise[T.nilable(T.type_parameter(:U))])
      end
      def self.load(model, id, column: :id, security_violation_behaviour: :raise, security_unavailable_behavior: :raise, case_sensitive: true, shard_key: nil)
        self.for(model, column, case_sensitive: case_sensitive, shard_key:).load(id, security_violation_behaviour: security_violation_behaviour, security_unavailable_behavior: security_unavailable_behavior)
      end

      sig do
        type_parameters(:U)
        .params(
          model: T.any(::ActiveRecord::Relation, T::Class[T.all(T.type_parameter(:U), ::ActiveRecord::Base)]),
          ids: T::Enumerable[T.untyped],
          column: Symbol,
          security_violation_behaviour: Symbol,
          security_unavailable_behavior: Symbol,
          case_sensitive: T::Boolean,
          candidate_user_permission_check: T::Boolean,
          shard_key: T.nilable(T::Hash[T.any(Symbol, String), Integer]),
        ).returns(Promise[T::Array[T.nilable(T.type_parameter(:U))]])
      end
      def self.load_all(model, ids, column: :id, security_violation_behaviour: :raise, security_unavailable_behavior: :raise, case_sensitive: true, candidate_user_permission_check: false, shard_key: nil)
        loader = self.for(model, column, case_sensitive: case_sensitive, shard_key:)
        Promise.all(ids.map { |id| loader.load(id, security_violation_behaviour: security_violation_behaviour, security_unavailable_behavior: security_unavailable_behavior, candidate_user_permission_check: candidate_user_permission_check) })
      end

      def self.load_relation(relation)
        load_all(relation.klass, relation.pluck(:id))
      end

      def load(id, security_violation_behaviour: :raise, security_unavailable_behavior: :raise, candidate_user_permission_check: false)
        super(id).then do |object|
          # The Platform layer mostly relies on transitive access control (ie. if
          # the user has access to entity A, and entity B is accessible from entity
          # A, then they must have access to entity B).
          #
          # Care is taken where repositories are exposed to hide repositories that
          # the user does not have access to, but this is a last-ditch effort to
          # prevent accidental exposure if we miss a spot.
          #
          if object.is_a?(::Repository) && security_violation_behaviour != :allow
            Platform::Security::RepositoryAccess.async_guard(object, security_violation_behaviour: security_violation_behaviour, security_unavailable_behavior: security_unavailable_behavior, candidate_user_permission_check: candidate_user_permission_check)
          else
            object
          end
        end
      end

      def initialize(model, column = :id, case_sensitive: true, shard_key: nil)
        @model = model
        @column = column
        @case_sensitive = case_sensitive
        @case_insensitive_record_map = {}
        @shard_key = shard_key
      end

      def populate_case_insensitive_record_map!(ids)
        ids.each do |id|
          if id.is_a?(String)
            @case_insensitive_record_map[id.downcase] ||= []
            @case_insensitive_record_map[id.downcase] << id
          end
        end
      end

      def record_id_case_variants(id)
        if id.is_a?(String) && !@case_sensitive
          @case_insensitive_record_map[id.downcase] || [id]
        else
          [id]
        end
      end

      def fetch(ids)
        populate_case_insensitive_record_map!(ids) unless @case_sensitive
        record_map = {}

        # Use with_logins scope when loading users/orgs by login for multi-tenancy support
        use_with_logins_scope = (@model == ::User || @model == ::Organization) && @column == :login

        records = if [::Status, ::CheckSuite, ::CheckRun, ::CheckStep, ::CheckAnnotation, ::Actions::WorkflowRun, ::Push].include?(@model)
          if @shard_key.present?
            shard_column, shard_id = @shard_key.first
            @model.where(@column => ids).where(shard_column => shard_id).to_a
          else
            GitHub::SQLCheckers::TableSharding.allowing_cross_shard_queries do
              @model.where(@column => ids).to_a
            end
          end
        elsif use_with_logins_scope
          @model.with_logins(ids).to_a
        else
          @model.where(@column => ids).to_a
        end

        records.each do |record|
          record_id_case_variants(record[@column]).each do |id|
            # Prefer first record if there's a column collision.
            record_map[id] ||= record

            if use_with_logins_scope
              # Support loading via unique login or display login or specifically-cased login from #load
              display_login = User.to_display_login(id)
              record_map[display_login] ||= record

              next if @case_sensitive

              @case_insensitive_record_map[display_login.downcase]&.each do |login|
                record_map[login] ||= record
              end
            end
          end
        end

        record_map
      end

      def dog_tags
        ["model:#{@model.name.underscore}"]
      end
    end
  end
end
