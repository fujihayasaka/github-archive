# typed: strict
# frozen_string_literal: true

# Destroy dependent records for a model in the background. Destruction is
# performed in throttled manner in order to be friendly to the database. The
# work may take place via a series of jobs, to avoid having a single
# long-running job.
#
# Job arguments:
#
# model_name            - The String class name of the model (e.g., "Repository").
# parent_model_id       - The Integer primary key id of the deleted model. The model
#                         will have been deleted already, but not the related records.
# association_name      - The Symbol name of the association which off of the model (e.g., "commit_contributions").
# inverse_relationship  - Invert the association relationship
#                         - "Repository", 42, :issues, inverse_relationship: false
#                             will find Repository 42 and delete the records in association :issues.
#                         - "Issue", 42, :repository, inverse_relationship: true
#                             will find and delete Issues that have a :repository association with record 42
# options               - Options for sharding (sharding_key and sharding_value and parent_sharding_key and parent_sharding_value).
#                         Additionally cross_shard_query_exempted allows
#                         a temporary reprieve from cross_shard_query linter errors.
class DestroyDependentRecordsJob < BatchedJob
  DEFAULT_QUEUE_NAME = :background_destroy

  queue_as do
    T.bind(self, DestroyDependentRecordsJob)

    # Tests validate queue_name without passing any arguments
    model_name = arguments.first
    association_name = arguments.third
    next DEFAULT_QUEUE_NAME if model_name.nil? || association_name.nil?

    table_model_class.dedicated_background_destroy_queue_name || DEFAULT_QUEUE_NAME
  end

  retry_on_dirty_exit
  retry_on_recoverable_exceptions
  retry_on ActiveRecord::AdapterTimeout
  retry_on ActiveRecord::ConnectionFailed
  retry_on ActiveRecord::ConnectionNotEstablished
  retry_on Freno::Throttler::WaitedTooLong, wait: :polynomially_longer, attempts: 15

  exempt_from_tenant_context_requirement

  class DestroyDependentRecordsError < RuntimeError; end

  before_perform :populate_failbot_context
  before_perform :ensure_parent_record_is_deleted
  before_perform { GitHub.dogstats.increment("destroy_dependent_records", tags: tags) }

  around_perform do |_job, block|
    @records_destroyed = T.let(0, T.nilable(Integer))
    @records_not_destroyed = T.let(0, T.nilable(Integer))
    block.call
    GitHub.dogstats.count("destroy_dependent_records.records_destroyed", @records_destroyed, tags: tags)

    if T.must(@records_not_destroyed) > 0
      GitHub.dogstats.count("destroy_dependent_records.records_not_destroyed", @records_not_destroyed, tags: tags)
    end
  end

  around_perform do |_job, block|
    GitHub::DomainIsolation.within_domain_of(table_model_class, &block)
  end

  sig do
    params(
      model_name: String,
      parent_model_id: GitHub::BackgroundDeletes::ID,
      association_name: Symbol,
      timestamp: Time,
      offset_item_id: Integer,
      polymorphic_type_value: T.nilable(Integer),
      polymorphic_class_name: T.nilable(String),
      initial_start: T.nilable(Time),
      sharding_key: T.nilable(Symbol),
      sharding_value: T.nilable(Integer),
      parent_sharding_key: T.nilable(Symbol),
      parent_sharding_value: T.nilable(Integer),
      cross_shard_query_exempted: T::Boolean,
      inverse_relationship: T::Boolean,
      options: T::Hash[Symbol, T.untyped],
    ).returns(ActiveRecord::Relation)
  end
  def next_batch(
    model_name,
    parent_model_id,
    association_name,
    timestamp: Time.now.utc,
    offset_item_id: 0,
    polymorphic_type_value: nil,
    polymorphic_class_name: nil,
    initial_start: nil,
    sharding_key: nil,
    sharding_value: nil,
    parent_sharding_key: nil,
    parent_sharding_value: nil,
    cross_shard_query_exempted: false,
    inverse_relationship: false,
    **options
  )
    sql_bindings = {
      table: table_model_table_name,
      foreign_key: table_model_foreign_key,
      sharding_column: sharding_column,
      sharding_value: sharding_value,
      type_column: table_model_type_column,
      type_value: table_model_type_value,
      parent_model_id: parent_model_id,
      last_seen: offset_item_id,
      count: Arel.sql(BATCH_SIZE.to_s),
    }
    sql = Arel.sql <<-SQL.squish, **sql_bindings
      SELECT id FROM :table
      WHERE :foreign_key = :parent_model_id
      AND id > :last_seen
    SQL

    custom_conditions = custom_sql_conditions_for_next_batch
    sql += custom_conditions unless custom_conditions.blank?

    if polymorphic?
      sql += Arel.sql <<-SQL.squish, **sql_bindings
        AND :type_column = :type_value
      SQL
    end

    if sharding_key && sharding_value
      sql += Arel.sql <<-SQL.squish, **sql_bindings
        AND :sharding_column = :sharding_value
      SQL
    end

    if cross_shard_query_exempted?
      sql += Arel.sql <<-SQL.squish
        /* cross-shard-query-exempted */
      SQL
    end

    sql += Arel.sql <<-SQL.squish, **sql_bindings
      ORDER BY id
      LIMIT :count
    SQL

    ids = table_model_class.connection.select_values(sql)

    return table_model_class.none if ids.empty?

    if sharding_key && sharding_value
      records = table_model_class.where(:id => ids, sharding_key => sharding_value)
    else
      records = table_model_class.where(id: ids)
    end

    if cross_shard_query_exempted?
      records = records.annotate("cross-shard-query-exempted")
    end

    records
  end

  sig do
    params(records: ActiveRecord::Relation, args: T.untyped, options: T.untyped).void
  end
  def process_batch(records, *args, **options)
    records.each do |record|
      record.throttle_writes do
        record.transaction do
          if record.destroy # could silently fail?
            @records_destroyed = T.let(T.must(@records_destroyed) + 1, T.nilable(Integer))
          else
            @records_not_destroyed = T.let(T.must(@records_not_destroyed) + 1, T.nilable(Integer))

            GitHub.logger.warn(
              "Dependent record failed to be destroyed", {
                "code.namespace" => "DestroyDependentRecordsJob",
                "code.function" => "process_batch",
                "table_model" => record.class.name,
                "table_model_id" => record.id,
                "parent_model" => parent_model_name,
                "parent_model_id" => parent_model_id,
                "error" => record.errors.full_messages.join(","),
              }
            )
          end
        end
      end
    end
  end

  sig { returns(T.any(Arel::Nodes::SqlLiteral, Arel::Nodes::BoundSqlLiteral)) }
  def custom_sql_conditions_for_next_batch
    Arel.sql("")
  end

  private

  ##
  # Arguments
  #

  sig { returns(String) }
  def model_name
    arguments.first
  end

  sig { returns(T.class_of(ApplicationRecord::Base)) }
  def model_class
    model_name.constantize
  end

  sig { returns(GitHub::BackgroundDeletes::ID) }
  def parent_model_id
    arguments.second
  end

  sig { returns(Symbol) }
  def association_name
    arguments.third
  end

  sig { returns(GitHub::BackgroundDeletes::Options) }
  def options
    GitHub::BackgroundDeletes::Options.from_hash(arguments.fourth || {})
  end

  sig { returns(T.nilable(Symbol)) }
  def sharding_key
    options.sharding_key
  end

  sig { returns(T.nilable(GitHub::BackgroundDeletes::ID)) }
  def sharding_value
    options.sharding_value
  end

  sig { returns(T.nilable(Symbol)) }
  def parent_sharding_key
    options.parent_sharding_key
  end

  sig { returns(T.nilable(GitHub::BackgroundDeletes::ID)) }
  def parent_sharding_value
    options.parent_sharding_value
  end

  sig { returns(T::Boolean) }
  def cross_shard_query_exempted?
    options.cross_shard_query_exempted
  end

  sig { returns(T.nilable(Integer)) }
  def polymorphic_type_value
    options.polymorphic_type_value
  end

  sig { returns(T.nilable(String)) }
  def polymorphic_class_name
    options.polymorphic_class_name
  end

  sig { returns(T::Boolean) }
  def inverse_relationship?
    options.inverse_relationship
  end

  sig { returns(T.nilable(Arel::Nodes::SqlLiteral)) }
  def sharding_column
    sharding_key ? Arel.sql(sharding_key.to_s) : nil
  end

  ##
  # Parent model
  #
  # Parent model is the record that was destroyed to trigger this job
  #

  sig { returns(String) }
  def parent_model_name
    inverse_relationship? ? association_class_name : model_name
  end

  sig { returns(T.class_of(ApplicationRecord::Base)) }
  def parent_model_class
    parent_model_name.constantize
  end

  sig { returns(String) }
  def parent_model_catalog_service
    GitHub.serviceowners&.service_for_class(parent_model_class, prefix: true) || GitHub::Serviceowners::UNKNOWN_SERVICE
  end

  ##
  # Table model
  #
  # Table model is the records that should be deleted by this job
  #

  sig { returns(String) }
  def table_model_name
    inverse_relationship? ? model_name : association_class_name
  end

  sig { returns(T.class_of(ApplicationRecord::Base)) }
  def table_model_class
    table_model_name.constantize
  end

  sig { returns(String) }
  def table_model_catalog_service
    GitHub.serviceowners&.service_for_class(table_model_class, prefix: true) || GitHub::Serviceowners::UNKNOWN_SERVICE
  end

  sig { returns(Arel::Nodes::SqlLiteral) }
  def table_model_table_name
    Arel.sql(table_model_class.table_name)
  end

  sig { returns(Arel::Nodes::SqlLiteral) }
  def table_model_foreign_key
    Arel.sql(association.foreign_key)
  end

  sig { returns(T.nilable(Arel::Nodes::SqlLiteral)) }
  def table_model_type_column
    type_column = inverse_relationship? ? association.foreign_type : association.type
    type_column ? Arel.sql(type_column) : nil
  end

  sig { returns(T.any(T.nilable(Integer), String)) }
  def table_model_type_value
    polymorphic_type_value || parent_model_name
  end

  sig { returns(T::Boolean) }
  def polymorphic?
    (inverse_relationship? ? association.foreign_type : association.type).present?
  end

  ## Association
  #
  # The association off of the model_name argument
  #

  sig { returns(String) }
  def association_class_name
    T.must(association_class.name)
  end

  sig { returns(T.class_of(ApplicationRecord::Base)) }
  def association_class
    if inverse_relationship? && polymorphic_class_name.present?
      T.must(polymorphic_class_name).constantize
    elsif inverse_relationship? && polymorphic_type_value.present?
      model_name.constantize.send("#{association_name}_types").invert[polymorphic_type_value].constantize
    else
      association.klass
    end
  end

  # Returns the AssociationReflection for the association being destroyed (i.e.,
  # the dependent).
  sig { returns(T.any(ActiveRecord::Reflection::AssociationReflection, ActiveRecord::Reflection::ThroughReflection)) }
  def association
    # For some security, use reflection to retrieve the table name rather than
    # relying on user input in the job arguments.
    model_class.reflect_on_association(association_name)
  end

  # Returns an Array of Strings representing the tags to include with Datadog
  # metrics reported by this job.
  sig { returns(T::Array[String]) }
  def tags
    [
      "parent_model:#{parent_model_name.underscore.dasherize}",
      "parent_model_catalog_service:#{parent_model_catalog_service}",
      "association:#{association_name.to_s.dasherize}",
      "table_model:#{table_model_name.underscore.dasherize}",
      "table_model_catalog_service:#{table_model_catalog_service}",
      "queue:#{queue_name}",
      "cluster:#{table_model_class.cluster_name}",
      "inverse_relationship:#{inverse_relationship?}",
      "cross_shard_query_exempted:#{cross_shard_query_exempted?}",
    ].compact
  end

  # Invoked as a before_perform callback.
  #
  # Populates the Failbot context for an invocation of this job.
  sig { void }
  def populate_failbot_context
    Failbot.push \
      "gh.dependency.parent_model.name": parent_model_name,
      "gh.dependency.parent_model.id": parent_model_id,
      "gh.dependency.table_model.name": table_model_name
  end

  sig { returns(T::Boolean) }
  def shared_parent_query?
    !!(parent_sharding_key && parent_sharding_value)
  end

  # Invoked as a before_perform callback.
  #
  # Aborts the job early if the record has been restored prior to the job
  # running. Affects repository records that have been restored while jobs are
  # backed up. See https://github.com/github/github/issues/74145.
  sig { void }
  def ensure_parent_record_is_deleted
    is_parent_record_deleted =
      ActiveRecord::Base.connected_to(role: :writing, prevent_writes: true) do
        record = if shared_parent_query?
          parent_model_class.find_by(:id => parent_model_id, parent_sharding_key => parent_sharding_value)
        else
          parent_model_class.find_by(id: parent_model_id)
        end
        record.nil? || !record.respond_to?(:deleted?) || record.deleted?
      end

    return if is_parent_record_deleted

    error = DestroyDependentRecordsError.new("Dependents parent record is not deleted")
    Failbot.report(error)
    throw(:abort)
  end
end
