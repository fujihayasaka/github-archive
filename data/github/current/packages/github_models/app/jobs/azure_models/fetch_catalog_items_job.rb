# typed: strict
# frozen_string_literal: true

module AzureModels
  class FetchCatalogItemsJob < ApplicationJob

    locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC

    queue_as :marketplace
    schedule interval: 1.hour, condition: -> { GitHub.models_enabled? }
    exempt_from_tenant_context_requirement

    sig { void }
    def perform
      unless GitHub.flipper[:project_neutron_fetch_catalog_items_job].enabled?
        GitHub.logger.info("Skipping AzureModels::FetchCatalogItemsJob. project_neutron_fetch_catalog_items_job is disabled")
        return
      end

      GitHub.logger.info("Starting AzureModels::FetchCatalogItemsJob")

      all_models = AzureModels::Client.fetch_models

      all_models = all_models.filter do |model|
        model_id = "azureml://registries/#{model[:registry]}/models/#{model[:original_name]}"
        GitHubModels::Payloads::GettingStartedContent.fetch(model_id.to_sym).present?
      end

      with_write do
        all_models_catalog_item = AzureModels::CatalogItem.find_by(key: "all_models")
        all_models_catalog_item ||= AzureModels::CatalogItem.new(key: "all_models")
        all_models_catalog_item.update!(value: all_models.to_json)
        # Update the updated_at timestamp so we know when the catalog was last updated whether or not there were changes
        all_models_catalog_item.touch(:updated_at)
      end

      GitHub.logger.info("Updated the catalog for #{all_models.count} models from Azure")

      all_models.each do |model|
        # Use the original name here so the API knows which model we mean when there's a `.` in the name
        model_details = AzureModels::Client.fetch_model(
          registry: model[:registry],
          model_name: model[:original_name],
          version: model[:model_version],
        )

        key = "#{model[:registry]}/#{model[:name]}"

        if model_details.present? && model_details[:model].present?
          model_details[:model][:dark_mode_icon] = model[:dark_mode_icon]
          model_details[:model][:light_mode_icon] = model[:light_mode_icon]
        end

        with_write do
          model_catalog_item = AzureModels::CatalogItem.find_by(key: key)
          model_catalog_item ||= AzureModels::CatalogItem.new(key: key)
          model_catalog_item.update!(value: model_details.to_json)
          model_catalog_item.synchronize_search_index
        end

        GitHub.logger.info("Updated details for #{model[:registry]}/#{model[:name]}")
      rescue AzureModels::Client::ApiError => e
        GitHub.dogstats.increment("github_models.catalog_sync_failure", tags: ["model:#{model[:name]}"])
        GitHub::Chatterbox.client.say!("#github-models-ops", "Couldn't sync details for #{model[:name]}, error: #{e.message}")
        GitHub.logger.error("Skipping over model", e.message)
      end

      models_not_in_index = AzureModels::CatalogItem.where.not(key:
        ["all_models", *all_models.map { |m| "#{m[:registry]}/#{m[:name]}" }]
      )

      models_not_in_index.each do |model|
        model.synchronize_search_index(deleting: true)
        with_write do
          model.destroy
        end
      end
    end
  end
end
