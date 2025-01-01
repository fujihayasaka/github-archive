# typed: true
# frozen_string_literal: true

module Search
  class AzureModelResultView
    include AzureModels::Parseable

    # Create a new AzureModelResultView from a `azure_model` document hash
    # returned from the ElasticSearch index.
    #
    # hash - Document Hash returned by ElasticSearch
    #
    def initialize(hash)
      @id = hash["_id"]
    end

    sig { returns(T.nilable(GitHubModels::Types::SerializedListing)) }
    def for_frontend_rendering
      catalog_item = AzureModels::CatalogItem.find_by(id: @id)
      return nil if catalog_item.nil?

      model = catalog_item.parsed_value.dig(:model)
      model = cast_types(model)
      model[:type] = "model"
      model[:model_url] = "/marketplace/models/#{model[:registry]}/#{model[:name]}"
      model
    end

    private

    sig { params(untyped_model: T::Hash[Symbol, T.untyped]).returns(GitHubModels::Types::SerializedListing) }
    def cast_types(untyped_model)
      T.let({
        id: untyped_model[:id].to_s,
        registry: untyped_model[:registry].to_s,
        name: untyped_model[:name].to_s,
        original_name: untyped_model[:original_name].to_s,
        friendly_name: untyped_model[:friendly_name].to_s,
        task: untyped_model[:task].to_s,
        publisher: untyped_model[:publisher].to_s,
        license: untyped_model[:license].to_s,
        description: untyped_model[:description].to_s,
        summary: untyped_model[:summary].to_s,
        model_family: untyped_model[:model_family].to_s,
        model_version: untyped_model[:model_version].to_s,
        notes: untyped_model[:notes].to_s,
        tags: T.let(untyped_model[:tags] || [], T::Array[String]),
        rate_limit_tier: untyped_model[:rate_limit_tier].to_s,
        supported_languages: T.let(untyped_model[:supported_languages] || [], T::Array[String]),
        max_output_tokens: untyped_model[:max_output_tokens].to_i,
        max_input_tokens: untyped_model[:max_input_tokens].to_i,
        training_data_date: untyped_model[:training_data_date].to_s,
        logo_url: untyped_model[:logo_url].to_s,
        dark_mode_icon: untyped_model[:dark_mode_icon].to_s,
        light_mode_icon: untyped_model[:light_mode_icon].to_s,
        evaluation: untyped_model[:evaluation].to_s,
        license_description: untyped_model[:license_description].to_s,
        static_model: !!untyped_model[:static_model],
        supported_input_modalities: T.let(untyped_model[:supported_input_modalities] || [], T::Array[String]),
        supported_output_modalities: T.let(untyped_model[:supported_output_modalities] || [], T::Array[String]),
        type: untyped_model[:type].to_s,
        model_url: untyped_model[:model_url].to_s,
      }, GitHubModels::Types::SerializedListing)
    end
  end
end
