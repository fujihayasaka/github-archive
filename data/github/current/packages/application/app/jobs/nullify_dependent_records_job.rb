# typed: strict
# frozen_string_literal: true

class NullifyDependentRecordsJob < ApplicationJob
  extend T::Sig

  default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

  queue_as :background_destroy

  retry_on_dirty_exit

  retry_on StandardError

  SELECT_BATCH_SIZE = 10000
  NULLIFY_BATCH_SIZE = 100

  # Nullify dependent records for a model.
  #
  # model_name       - The String class name of the parent model, e.g. Repository
  # model_id         - The Integer primary key id of the parent model.
  # association_name - The Symbol name of the dependent association which needs
  #                    to be nullified, e.g. :sponsors_tiers
  sig { params(model_name: String, model_id: T.any(Integer, String), association_name: Symbol).void }
  def perform(model_name, model_id, association_name)
    Failbot.push \
      "gh.repo.nullify_dependent_records_job.model.name": model_name,
      "gh.repo.nullify_dependent_records_job.model.id": model_id,
      "gh.repo.nullify_dependent_records_job.association_name": association_name

    model       = model_name.constantize
    association = model.reflect_on_association(association_name.to_sym)
    # Determine table, foreign key and type information for the association.
    table       = Arel.sql(association.klass.table_name)
    foreign_key = Arel.sql(association.foreign_key)
    type_column = Arel.sql(association.type.to_s) # may be nil
    type_value  = model.name

    tags = ["model:#{model_name.underscore.dasherize}", "association:#{association_name.to_s.dasherize}"]

    rows_nullified = T.let(0, Integer)
    last_seen = T.let(0, T.any(Integer, String))
    loop do
      ids = ActiveRecord::Base.connected_to(role: :reading) do
        sql_bindings = {
          table: table,
          foreign_key: foreign_key,
          type_column: type_column,
          type_value: type_value,
          model_id: model_id,
          last_seen: last_seen,
          count: Arel.sql(SELECT_BATCH_SIZE.to_s)
        }
        sql = Arel.sql <<-SQL, **sql_bindings
              SELECT id FROM :table
              WHERE :foreign_key = :model_id
              AND id > :last_seen
        SQL

        if !association.type.blank? # we've got a polymorphic association
          sql += Arel.sql <<-SQL, **sql_bindings
                AND :type_column = :type_value
          SQL
        end

        sql += Arel.sql <<-SQL, **sql_bindings
              ORDER BY id
              LIMIT :count
        SQL
        association.klass.connection.select_values(sql)
      end

      break if ids.empty?
      last_seen = T.let(ids.last, T.any(Integer, String))

      ids.each_slice(NULLIFY_BATCH_SIZE) do |slice|
        klass = association.klass
        klass.throttle do
          if !association.type.blank?
            # Clear out type information on polymorphic associations
            affected_rows = klass.connection.update(Arel.sql(<<~SQL, table: table, ids: slice, foreign_key: foreign_key, type_column: type_column))
              UPDATE :table SET :foreign_key = NULL, :type_column = NULL WHERE id IN (:ids)
            SQL
          else
            affected_rows = klass.connection.update(Arel.sql(<<~SQL, table: table, ids: slice, foreign_key: foreign_key))
              UPDATE :table SET :foreign_key = NULL WHERE id IN (:ids)
            SQL
          end
          rows_nullified += affected_rows
        end
      end
    end

    GitHub.dogstats.distribution("job.nullify_dependent_records.dist.rows", rows_nullified, tags: tags)
  end
end
