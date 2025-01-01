# typed: true
# frozen_string_literal: true

class RepairDiscussionsIndexJob < Elastomer::RepairJob
  queue_as :index_bulk

  reconcile "discussion",
    fields: %w[updated_at],
    limit: 500,
    model_class: Discussion,
    reject: :orphaned?
end
