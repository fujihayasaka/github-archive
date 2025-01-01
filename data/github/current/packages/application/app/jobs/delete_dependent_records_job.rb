# typed: strict
# frozen_string_literal: true

class DeleteDependentRecordsJob < ApplicationJob
  DEFAULT_QUEUE_NAME = :background_destroy

  queue_as do
    T.bind(self, DeleteDependentRecordsJob)

    # Tests validate queue_name without passing any arguements
    model_name = arguments.first
    association_name = arguments.third

    next DEFAULT_QUEUE_NAME if model_name.nil? || association_name.nil?

    table_model_class.dedicated_background_destroy_queue_name || DEFAULT_QUEUE_NAME
  end

  retry_on_dirty_exit

  retry_on StandardError

  exempt_from_tenant_context_requirement

  SELECT_BATCH_SIZE = 10000
  DELETE_BATCH_SIZE = 100

  around_perform do |_job, block|
    GitHub::DomainIsolation.within_domain_of(table_model_class, &block)
  end

  # Perform a throttled deletion of the dependent records for a model.
  #
  # model_name       - The String class name of the parent model, e.g. Repository
  # model_id         - The Integer primary key id of the parent model. The model
  #                    will have been deleted already, but not these
  #                    dependent records.
  # association_name - The Symbol name of the dependent association which needs
  #                    to be cleared, e.g. :commit_contributions
  sig do
    params(
      model_name: String,
      model_id: T.any(Integer, String),
      association_name: Symbol,
      polymorphic_class_name: T.nilable(String),
      sharding_key: T.nilable(Symbol),
      sharding_value: T.nilable(Integer),
      polymorphic_type_value: T.nilable(GitHub::BackgroundDeletes::ID),
      inverse_relationship: T.nilable(T::Boolean)
    ).void
  end
  def perform(model_name, model_id, association_name, polymorphic_class_name: nil, sharding_key: nil, sharding_value: nil, polymorphic_type_value: nil, inverse_relationship: nil)
    Failbot.push \
      model_name: model_name,
      model_id: model_id,
      association_name: association_name

    tags = ["model:#{model_name.underscore.dasherize}", "association:#{association_name.to_s.dasherize}", "inverse_relationship:#{inverse_relationship.present?}"]

    rows_deleted = 0
    last_seen = T.let(0, GitHub::BackgroundDeletes::ID)

    loop do
      bindings = {
        table: table_name,
        foreign_key: foreign_key,
        sharding_column: sharding_column,
        sharding_value: sharding_value,
        type_column: type_column,
        type_value: table_model_type_value,
        model_id: model_id,
        last_seen: last_seen,
        count: Arel.sql(SELECT_BATCH_SIZE.to_s)
      }
      sql = Arel.sql(<<-SQL, **bindings)
            SELECT id FROM :table
            WHERE :foreign_key = :model_id
            AND id > :last_seen
      SQL

      if polymorphic?
        sql += Arel.sql(<<-SQL, **bindings)
              AND :type_column = :type_value
        SQL
      end

      if sharding_key && sharding_value
        sql += Arel.sql(<<-SQL, **bindings)
          AND :sharding_column = :sharding_value
        SQL
      end

      sql += Arel.sql(<<-SQL, **bindings)
            ORDER BY id
            LIMIT :count
      SQL

      ids = table_model_class.connection.select_values(sql)

      break if ids.empty?
      last_seen = T.let(ids.last, GitHub::BackgroundDeletes::ID)

      ids.each_slice(DELETE_BATCH_SIZE) do |slice|
        table_model_class.throttle_writes do
          affected_rows = if sharding_key && sharding_value
            table_model_class.connection.delete(Arel.sql(<<~SQL, table: table_name, ids: slice, sharding_column: sharding_column, sharding_value: sharding_value))
              DELETE FROM :table WHERE id IN (:ids) AND :sharding_column = :sharding_value
            SQL
          else
            table_model_class.connection.delete(Arel.sql(<<~SQL, table: table_name, ids: slice))
              DELETE FROM :table WHERE id IN (:ids)
            SQL
          end
          rows_deleted += affected_rows

          # If we are archiving a `Storage::Uploadable` model, we dereference it so that if
          # a purge job needs to be scheduled, it can be. Since the models are not `#destroy`'d, the
          # registered `after_destroy` callbacks are not called, this does nearly equivalent work.
          if table_model_class.try(:act_on_storage_uploadable?)
            slice.each do |id|
              GitHub::Storage::Destroyer.dereference_raw(table_model_class, id, purge_at: T.let(table_model_class, T.untyped).purge_at)
            end
          end
        end
      end
    end

    GitHub.dogstats.distribution("job.delete_dependent_records.dist.rows", rows_deleted, tags: tags)
  end

  # Arguments
  sig { returns(GitHub::BackgroundDeletes::Options) }
  def options
    GitHub::BackgroundDeletes::Options.from_hash(arguments.fourth || {})
  end

  sig { returns(String) }
  def model_name
    arguments.first
  end

  sig { returns(T.class_of(ApplicationRecord::Base)) }
  def model_class
    model_name.constantize
  end

  sig { returns(String) }
  def parent_model_name
    inverse_relationship? ? T.must(association_class.name) : model_name
  end

  sig { returns(Symbol) }
  def association_name
    arguments.third
  end

  sig { returns(T.nilable(String)) }
  def polymorphic_class_name
    options.polymorphic_class_name
  end

  sig { returns(T::Boolean) }
  def inverse_relationship?
    options.inverse_relationship
  end

  sig { returns(T.nilable(Symbol)) }
  def sharding_key
    options.sharding_key
  end

  sig { returns(T.nilable(GitHub::BackgroundDeletes::ID)) }
  def sharding_value
    options.sharding_value
  end

  sig { returns(T.nilable(Arel::Nodes::SqlLiteral)) }
  def sharding_column
    sharding_key ? Arel.sql(sharding_key.to_s) : nil
  end

  sig { returns(T.nilable(GitHub::BackgroundDeletes::ID)) }
  def polymorphic_type_value
    options.polymorphic_type_value
  end

  # Association
  sig { returns(ActiveRecord::Reflection::AssociationReflection) }
  def association
    model_class.reflect_on_association(association_name)
  end

  sig { returns(T.class_of(ApplicationRecord::Base)) }
  def association_class
    if inverse_relationship? && polymorphic_class_name.present?
      T.must(polymorphic_class_name).constantize
    else
      association.klass
    end
  end

  sig { returns(Arel::Nodes::SqlLiteral) }
  def foreign_key
    Arel.sql(association.foreign_key)
  end

  # Table Model, the model being deleted
  sig { returns(T.class_of(ApplicationRecord::Base)) }
  def table_model_class
    inverse_relationship? ? model_class : association_class
  end

  sig { returns(Arel::Nodes::SqlLiteral) }
  def table_name
    Arel.sql(table_model_class.table_name)
  end

  # Polymorphic Type
  sig { returns(T.nilable(Arel::Nodes::SqlLiteral)) }
  def type_column
    type_column = inverse_relationship? ? association.foreign_type : association.type
    type_column ? Arel.sql(type_column) : nil
  end

  sig { returns(T.nilable(T.any(String, Integer))) }
  def table_model_type_value
    polymorphic_type_value || parent_model_name
  end

  sig { returns(T::Boolean) }
  def polymorphic?
    (inverse_relationship? ? association.foreign_type : association.type).present?
  end
end
