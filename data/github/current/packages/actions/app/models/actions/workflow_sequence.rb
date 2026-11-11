# typed: strict
# frozen_string_literal: true

class Actions::WorkflowSequence < ApplicationRecord::Domain::RepositoriesActionsChecks
  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain

  belongs_to :workflow,
    -> (workflow_sequence) { where(repository_id: workflow_sequence.repository_id) },
    class_name: "Actions::Workflow"

  class Error < RuntimeError; end

  # Checks whether a sequence exists for the given workflow.
  sig { params(workflow: Actions::Workflow).returns(T::Boolean) }
  def self.exists?(workflow)
    where(repository_id: workflow.repository_id, workflow_id: workflow.id).exists?
  end

  # Returns the current sequence number for the given workflow, or 0 if no
  # row exists. Mirrors `Sequence.get` so it can be used as a high-water-mark
  # check during dual-write loops.
  sig { params(workflow: Actions::Workflow).returns(Integer) }
  def self.get(workflow)
    where(repository_id: workflow.repository_id, workflow_id: workflow.id).pick(:number) || 0
  end

  # Creates a sequence row for the given workflow, starting at the specified value.
  # Silently ignores duplicate inserts (unique index on repository_id + workflow_id).
  sig { params(workflow: Actions::Workflow, start_value: Integer).returns(T.nilable(Actions::WorkflowSequence)) }
  def self.create(workflow, start_value = 0)
    create!(repository_id: workflow.repository_id, workflow_id: workflow.id, number: start_value)
  rescue ActiveRecord::RecordNotUnique
    # already exists
    nil
  end

  # Creates a sequence row if missing, or sets the existing sequence to at least the given value.
  sig { params(workflow: Actions::Workflow, number: Integer).returns(Integer) }
  def self.set_or_create(workflow, number)
    # rubocop:disable GitHub/InsertOnDuplicateKeyUpdate
    connection.insert(Arel.sql(<<~SQL, repository_id: workflow.repository_id, workflow_id: workflow.id, number: number))
      INSERT INTO workflow_sequences
        (repository_id, workflow_id, number, created_at, updated_at)
      VALUES
        (:repository_id, :workflow_id, :number, NOW(6), NOW(6))
      ON DUPLICATE KEY UPDATE
        `number` = LAST_INSERT_ID(GREATEST(`number`, CAST(:number AS SIGNED))),
        `updated_at` = NOW(6)
    SQL
    # rubocop:enable GitHub/InsertOnDuplicateKeyUpdate

    get(workflow)
  end

  # Increments the sequence by the given amount and returns the new value.
  # The sequence must already exist.
  sig { params(workflow: Actions::Workflow, increment: Integer).returns(Integer) }
  def self.next(workflow, increment = 1)
    scope = where(repository_id: workflow.repository_id, workflow_id: workflow.id)
    rows_updated = scope.update_all(["`number` = LAST_INSERT_ID(`number` + :increment), `updated_at` = NOW()", { increment: increment }])
    raise Error, "No workflow sequence for workflow #{workflow.id}" unless rows_updated == 1

    T.cast(connection.send(:last_insert_id), Integer)
  end

  # Atomically advances the sequence to at least `min_value`, returning the
  # new value. If the row is already at or past `min_value`, this is just a
  # normal +1 increment. Use this in gap-close loops rather than computing
  # the gap in Ruby and calling `next(workflow, gap)`: under concurrent
  # writers, the per-writer gap math overshoots (each writer jumps the row
  # by its observed gap, so two racing writers can produce visible
  # run_number jumps of ~gap each). GREATEST lets the row advance once and
  # every subsequent racing writer gets the natural +1.
  sig { params(workflow: Actions::Workflow, min_value: Integer).returns(Integer) }
  def self.next_at_least(workflow, min_value)
    scope = where(repository_id: workflow.repository_id, workflow_id: workflow.id)
    rows_updated = scope.update_all([
      "`number` = LAST_INSERT_ID(GREATEST(`number` + 1, CAST(:min_value AS SIGNED))), `updated_at` = NOW()",
      { min_value: min_value },
    ])
    raise Error, "No workflow sequence for workflow #{workflow.id}" unless rows_updated == 1

    T.cast(connection.send(:last_insert_id), Integer)
  end

  # Sets the sequence to at least the given value. The number will never decrease.
  # The sequence must already exist.
  sig { params(workflow: Actions::Workflow, number: Integer).returns(Integer) }
  def self.set(workflow, number)
    scope = where(repository_id: workflow.repository_id, workflow_id: workflow.id)
    rows_updated = scope.update_all(["`number` = LAST_INSERT_ID(GREATEST(`number`, CAST(:number AS SIGNED))), `updated_at` = NOW()", { number: number }])
    raise Error, "No workflow sequence for workflow #{workflow.id}" unless rows_updated == 1

    T.cast(connection.send(:last_insert_id), Integer)
  end
end
