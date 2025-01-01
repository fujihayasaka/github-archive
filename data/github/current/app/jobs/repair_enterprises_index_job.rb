# typed: true
# frozen_string_literal: true

class RepairEnterprisesIndexJob < Elastomer::RepairJob
  queue_as :index_bulk

  reconcile "enterprise", {
    model_class: Business,
    fields: ["updated_at"],
    limit: 250,
  }
end
