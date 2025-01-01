# typed: false
# frozen_string_literal: true

# Provides a mechanism for generating sequences of natural order numbers,
# uniquely scoped by a given context.
#
# The context should be responsible for coordinating the creation of resources
# sharing a number space.
#
# For example, a Repository is responsible for creating Issues and Pull Requests
# that share the same sequence such that no two distinct records will share the
# same number.
#
# Each number can be any type of record that the context auto-numbers. Each new
# record will be assigned the next available number. It's the context's
# responsibility to know how to find the record for a given number.
#
# It's assumed that once a number has been generated for the context, it should
# be considered taken and should not be reused or reassigned. These numbers
# represent stable reference points for users.
#
# This model is used exclusively for coordinating number generation within the
# given context and in parallel with all other contexts.
#
# NOTE: Resetting a sequence is a destructive action, deleting it. In practice,
# it should never be done on production.
module Sequence
  class Error < RuntimeError; end

  # Public: Creates a sequence for the given context.
  #
  # Returns nothing.
  def self.create(context, default = 0)
    if sequence_class = extracted_context_sequence_class(context)
      sequence_class.create!(
        extracted_context_sequence_column_with_value(context).merge(number: default),
      )
    else
      sql_bindings = prepare_query_bindings(context, default: default)
      sql = Arel.sql(<<-SQL, **sql_bindings)
        INSERT INTO sequences (context_type, context_id, number, created_at, updated_at)
        VALUES (:context_type, :context_id, :default, NOW(), NOW())
      SQL
      # demand a write connection to avoid https://github.com/github/repos/issues/7144
      ActiveRecord::Base.connected_to(role: :writing) do
        ApplicationRecord::Domain::Sequences.connection.insert(sql)
      end
    end

    nil
  rescue ActiveRecord::RecordNotUnique
  end

  # Public: Checks to see if a sequence exists for a given context.
  #
  # Returns true if it exists, false otherwise.
  def self.exists?(context)
    if sequence_class = extracted_context_sequence_class(context)
      sequence_class.where(extracted_context_sequence_column_with_value(context)).exists?
    else
      sql_bindings = prepare_query_bindings(context)
      sql = Arel.sql(<<-SQL, **sql_bindings)
        SELECT count(id) FROM sequences
        WHERE context_type = :context_type AND context_id = :context_id
        LIMIT 1
      SQL

      ApplicationRecord::Domain::Sequences.connection.select_value(sql).to_i == 1
    end
  end

  # Public: Returns the current sequence number Integer for the context.
  def self.get(context)
    if sequence_class = extracted_context_sequence_class(context)
      sequence_class.where(extracted_context_sequence_column_with_value(context)).pluck(:number).first
    else
      sql_bindings = prepare_query_bindings(context)
      sql = Arel.sql(<<-SQL, **sql_bindings)
        SELECT number FROM sequences
        WHERE
          context_type = :context_type AND
          context_id = :context_id
        LIMIT 1
      SQL
      ApplicationRecord::Domain::Sequences.connection.select_value(sql).to_i
    end
  end

  # Set the current sequence number for the given context.
  #
  # Returns nothing.
  def self.set(context, number)
    if sequence_class = extracted_context_sequence_class(context)
      update_extracted_context_sequence(sequence_class, context, number: number)
    else
      ApplicationRecord::Domain::Sequences.connection.update(set_or_next_sequence_query(context, number: number))
    end

    nil
  end

  # Resets the sequence for the given context by removing the record.
  #
  # Returns nothing.
  def self.reset(context, force = Rails.env.test?)
    return unless force

    if sequence_class = extracted_context_sequence_class(context)
      sequence_class.where(extracted_context_sequence_column_with_value(context)).delete_all
    else
      sql_bindings = prepare_query_bindings(context)
      sql = Arel.sql(<<-SQL, **sql_bindings)
        DELETE FROM sequences
        WHERE context_type = :context_type AND context_id = :context_id
      SQL
      ApplicationRecord::Domain::Sequences.connection.delete(sql)
    end

    nil
  end

  # Return the explicitly specified sequence type, if present.
  # Otherwise, fall back to the class name of the context object
  def self.get_sequence_context_type(context)
    if context.is_a?(Sequence::Context)
      context.sequence_context_type
    else
      context.class.name
    end
  end

  # Return the explicitly specified sequence id, if present.
  # Otherwise, fall back to the id of the context object
  def self.get_sequence_context_id(context)
    if context.is_a?(Sequence::Context)
      context.sequence_context_id
    else
      context.id
    end
  end

  # Increments the sequence number for a given context.
  #
  # The sequence MUST be created before enumerating.
  #
  # Returns the next sequence number Integer, or raises if the sequence doesn't
  # exist.
  def self.next(context, increment = 1)
    number = nil
    GitHub.instrument "sequence.next", context: context do
      raise Error, "No sequence for context of type #{get_sequence_context_type(context)}" unless exists?(context)

      if sequence_class = extracted_context_sequence_class(context)
        update_extracted_context_sequence(sequence_class, context, increment: increment)

        # TODO: Call public method once this pull request is merged:
        #   https://github.com/github/trilogy-adapter/pull/201
        number = sequence_class.connection.send(:last_insert_id)
      else
        # By calling 'insert' on the connection, we get the last inserted ID, even though technically the query is
        # an update statement.
        number = ApplicationRecord::Domain::Sequences.connection.insert(set_or_next_sequence_query(context, increment: increment))
      end
    end

    number
  end

  # Internal: Returns SQL bindings for the context
  def self.prepare_query_bindings(context = nil, binds = {})
    if context
      context_type = get_sequence_context_type(context)
      context_id = get_sequence_context_id(context)

      binds = binds.merge(context_type: context_type, context_id: context_id)
    end

    binds
  end

  # Internal: Prepares the set/next query.
  #
  # Provide `increment` bind to increment the existing sequence.
  # Otherwise, provide `number` bind to set the sequence explicitly.
  #
  # Sequence must be created before running this.
  #
  # Returns a prepared Arel object ready to be executed.
  def self.set_or_next_sequence_query(context, binds = {})
    unless binds[:increment] || binds[:number]
      raise ArgumentError, ":increment or :number must be specified"
    end

    sql_bindings = prepare_query_bindings context, binds
    sql = Arel.sql <<-SQL
      UPDATE sequences SET
    SQL

    if binds[:increment]
      # increment the sequence by the provided amount
      sql += Arel.sql(<<-SQL, **sql_bindings)
        number     = LAST_INSERT_ID(number + :increment),
      SQL
    else
      # otherwise set the sequence explicitly
      sql += Arel.sql(<<-SQL, **sql_bindings)
        number     = LAST_INSERT_ID(:number),
      SQL
    end

    sql += Arel.sql <<-SQL
      updated_at = NOW()
    SQL

    # for the context's sequence
    sql += Arel.sql(<<-SQL, **sql_bindings)
      WHERE
        context_type = :context_type AND
        context_id   = :context_id
    SQL

    sql
  end

  def self.extracted_context_sequence_class(context)
    context.try(:sequence_type)
  end

  def self.extracted_context_sequence_column_with_value(context)
    case get_sequence_context_type(context)
    when "RepositoryVulnerabilityAlert::SequenceContext",
      "TokenScanResult",
      "Milestone"
      { repository_id: context[:repository_id] }
    else
      { context.model_name.singular => context }
    end
  end

  def self.update_extracted_context_sequence(sequence_class, context, number: nil, increment: nil)
    raise ArgumentError(":increment or :number must be specified") if number.nil? && increment.nil?

    update_sql = "".dup
    binds = {}

    if number
      update_sql << "`number` = LAST_INSERT_ID(:number)"
      binds[:number] = number
    else
      update_sql << "`number` = LAST_INSERT_ID(`number` + :increment)"
      binds[:increment] = increment
    end

    update_sql << ", `updated_at` = NOW()"

    sequence_class.where(extracted_context_sequence_column_with_value(context)).update_all([update_sql, binds])
  end
end
