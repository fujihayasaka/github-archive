# typed: strict
# frozen_string_literal: true

module GitHubModels
  class FetchCatalogItemsJob < GitHubModelsJob
    exempt_from_tenant_context_requirement

    locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
    schedule interval: 15.minutes, condition: -> { GitHub.models_enabled? }

    sig { void }
    def perform
      publishers_client = GitHubModels::AzureAiPublishersClient.new
      ai_studio_client = GitHubModels::AzureAiStudioClient.new

      publishers = publishers_client.fetch_publishers
      all_models = ai_studio_client.fetch_models(publishers: publishers)

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
        model_details = GitHubModels.domain.models.fetch_from_api(
          registry: model[:registry],
          model_name: model[:original_name],
          version: model[:model_version],
          ai_studio_client: ai_studio_client,
        )

        slug = GitHubModels.domain.models.slug_for(registry: model[:registry], name: model[:name])

        if model_details.present? && model_details[:model].present?
          model_details[:model][:dark_mode_icon] = model[:dark_mode_icon]
          model_details[:model][:light_mode_icon] = model[:light_mode_icon]

          # Model capabilities are returned from the catalog list endpoint, not the model details one
          model_details[:model][:model_capabilities] = model[:model_capabilities] || []
        end

        model_db_attrs = { value: model_details.to_json }

        with_write do
          # Work around domain model and dual-table writing complexity by making an additional query.
          existing_record = GitHubModels.domain.models.find(slug: slug)
          if existing_record.nil?
            GitHub.logger.info("Creating new model as hidden: #{slug}")
            GitHub::Chatterbox.client.say!("#github-models-ops", "Received a new model from Azure catalog: #{slug}, creating as hidden")
            model_db_attrs[:visibility] = :hidden
          end

          model_record = GitHubModels.domain.models.upsert(slug, model_db_attrs
            .merge(format_model_attributes(model_details, lowercased_publishers)))
          model_record.created_at == model_record.updated_at ? action = "Created" : action = "Updated"
          GitHub.logger.info("#{action} details for #{slug}")
        end

      rescue GitHubModels::ApiClient::ApiError => e
        GitHub.dogstats.increment("github_models.catalog_sync_failure", tags: ["model:#{model[:name]}"])
        GitHub::Chatterbox.client.say!("#github-models-ops", "Couldn't sync details for #{model[:name]}, error: #{e.message}")
        GitHub.logger.error("Skipping over model #{model[:name]}", e.message)
      end

      slugs_to_exclude = all_models.map do |m|
        GitHubModels.domain.models.slug_for(registry: m[:registry], name: m[:name])
      end
      models_not_in_index = GitHubModels.domain.models.find_many(slugs_to_exclude: slugs_to_exclude)

      models_not_in_index.each do |model|
        with_write do
          GitHubModels.domain.models.destroy(model)
        end
      end
    end

    private

    sig { params(model_details: T::Hash[Symbol, T.untyped], lowercased_publishers: T::Hash[String, GitHubModels::Publisher]).returns(T::Hash[Symbol, T.untyped]) }
    def format_model_attributes(model_details, lowercased_publishers)
      model_attributes = model_details[:model].slice(
        :name, :original_name, :friendly_name, :task, :license, :description, :summary, :notes,
        :tags, :rate_limit_tier, :supported_languages, :max_output_tokens, :max_input_tokens,
        :training_data_date, :evaluation, :license_description, :supported_input_modalities,
        :supported_output_modalities
      )
      model_attributes[:version] = model_details[:model][:model_version]
      model_attributes[:training_data_date] = Date.parse(model_details[:model][:training_data_date]&.to_s) rescue nil
      model_attributes[:model_schema] = model_details[:schema].to_json
      model_attributes[:models_publisher_id] = find_model_publisher_id(model_details, lowercased_publishers)

      if model_details[:schema][:behavior] == "Disabled"
        GitHub.logger.info("Hiding #{model_details[:model][:name]} because its schema.behavior is disabled")
        model_attributes[:visibility] = :hidden
      end

      model_attributes[:tags] = model_details[:model][:tags]
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
