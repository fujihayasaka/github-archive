# typed: strict
# frozen_string_literal: true

module GitHubModels
  class FetchCatalogItemsJob < GitHubModelsJob
    exempt_from_tenant_context_requirement

    locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
    schedule interval: 1.hour, condition: -> { GitHub.models_enabled? }

    gate_with_feature_flag :project_neutron_fetch_catalog_items_job

    sig { void }
    def perform
      publishers = GitHubModels::Client.fetch_publishers
      all_models = GitHubModels::Client.fetch_models(publishers: publishers)

      unless GitHub.flipper[:github_models_fetch_catalog_items_job_no_content_filter].enabled?
        all_models = all_models.filter do |model|
          model_id = "azureml://registries/#{model[:registry]}/models/#{model[:original_name]}"
          GitHubModels::Payloads::GettingStartedContent.fetch(model_id.to_sym).present?
        end
      end

      publisher_records = []

      publishers["value"]&.each do |publisher|

        name = publisher["publisherName"]

        with_write do
          publisher_record = GitHubModels::Publisher.find_by(name: name) || GitHubModels::Publisher.new(name: name)

          publisher_record.update!(
            dark_mode_icon: publisher["iconDark"], light_mode_icon: publisher["iconLight"])

          publisher_records << publisher_record
        end
      end

      lowercased_publishers = publisher_records.each_with_object({}) do |publisher, hash|
        hash[publisher.name.downcase] = publisher
      end

      all_models.each do |model|
        # Use the original name here so the API knows which model we mean when there's a `.` in the name
        model_details = GitHubModels::Client.fetch_model(
          registry: model[:registry],
          model_name: model[:original_name],
          version: model[:model_version],
        )

        key = GitHubModels::CatalogItem.key_for(registry: model[:registry], name: model[:name])

        if model_details.present? && model_details[:model].present?
          model_details[:model][:dark_mode_icon] = model[:dark_mode_icon]
          model_details[:model][:light_mode_icon] = model[:light_mode_icon]
          model_details[:model][:popularity] = model[:popularity]
        end

        catalog_item_attrs = { value: model_details.to_json }
        catalog_item_attrs[:popularity] = model[:popularity] if model[:popularity]

        with_write do
          model_catalog_item = GitHubModels::CatalogItem.find_by(key: key) || GitHubModels::CatalogItem.new(key: key)
          model_catalog_item.update!(catalog_item_attrs
            .merge(format_model_attributes(model_details, lowercased_publishers)))
          model_catalog_item.synchronize_search_index
        end

        GitHub.logger.info("Updated details for #{key}")
      rescue GitHubModels::Client::ApiError => e
        GitHub.dogstats.increment("github_models.catalog_sync_failure", tags: ["model:#{model[:name]}"])
        GitHub::Chatterbox.client.say!("#github-models-ops", "Couldn't sync details for #{model[:name]}, error: #{e.message}")
        GitHub.logger.error("Skipping over model", e.message)
      end

      models_not_in_index = GitHubModels::CatalogItem.where
        .not(key: all_models.map { |m| GitHubModels::CatalogItem.key_for(registry: m[:registry], name: m[:name]) })

      models_not_in_index.each do |model|
        model.synchronize_search_index(deleting: true)
        with_write do
          model.destroy
        end
      end
    end

    private

    sig { params(model_details: T::Hash[Symbol, T.untyped], lowercased_publishers: T::Hash[String, GitHubModels::Publisher]).returns(T::Hash[Symbol, T.untyped]) }
    def format_model_attributes(model_details, lowercased_publishers)
      model_attributes = model_details[:model].slice(
        :name, :original_name, :friendly_name, :task, :license, :description, :summary, :notes,
        :model_version, :tags, :rate_limit_tier, :supported_languages, :max_output_tokens, :max_input_tokens,
        :training_data_date, :evaluation, :license_description, :supported_input_modalities,
        :supported_output_modalities
      )
      model_attributes[:training_data_date] = Date.parse(model_details[:model][:training_data_date]&.to_s) rescue nil
      model_attributes[:schema] = model_details[:schema].to_json
      model_attributes[:github_models_publisher_id] = find_model_publisher_id(model_details, lowercased_publishers)
      model_attributes
    end

    sig { params(model_details: T::Hash[Symbol, T.untyped], lowercased_publishers: T::Hash[String, GitHubModels::Publisher]).returns(T.nilable(Integer)) }
    def find_model_publisher_id(model_details, lowercased_publishers)
      publisher_name = model_details.dig(:model, :publisher)&.downcase
      matching_publisher = lowercased_publishers[publisher_name]

      GitHub.logger.error(
        "Catalog Item has no matching publisher",
        "github_models_catalog_item_name": model_details[:model][:name]) unless matching_publisher
      matching_publisher&.id
    end
  end
end
