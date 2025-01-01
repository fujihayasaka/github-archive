# typed: true
# frozen_string_literal: true

class RepairLabelsIndexJob < Elastomer::RepairJob
  default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

  queue_as :index_bulk

  reconcile "label",
    fields: %w[updated_at],
    limit: 2_000
end
