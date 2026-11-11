# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# The purpose of this job is to reconcile the models with the index.
#
# To make this whole process faster, multiple repair jobs can be enqueued. The current offset
# into the topics table is stored in redis. Access to this value is coordinated via a shared
# mutex. Don't spin up too many repair jobs otherwise you'll kill the database or the search
# index or both.
class RepairWorkflowRunsIndexJob < Elastomer::RepairJob
  queue_as :index_bulk

  reconcile "workflow_run",
    fields: %w[updated_at],
    limit: 250,
    model_class: Actions::WorkflowRun,
    named_scopes: {
      # This exemption is copied from restore_user_from_spammy_job. AFAIK there is not a
      # better way to accomplish this.
      actor: -> (id) { Actions::WorkflowRun.annotate("cross-shard-query-exempted-permanent").where(actor_id: id) }
    }
end
