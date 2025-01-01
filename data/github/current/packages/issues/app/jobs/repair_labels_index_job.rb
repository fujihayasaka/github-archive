# typed: true
# frozen_string_literal: true

class RepairLabelsIndexJob < Elastomer::RepairJob
  queue_as :index_bulk

  reconcile "label",
    fields: %w[updated_at],
    limit: 2_000
end
