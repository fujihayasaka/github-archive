# typed: true
# frozen_string_literal: true

class RepairAzureModelsIndexJob < Elastomer::RepairJob
  extend ClassMethods
  default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

  queue_as :index_bulk

  retry_on_dirty_exit

  reconcile "azure_model",
    fields: %w[updated_at],
    limit: 500,
    model_class: AzureModels::CatalogItem
end
