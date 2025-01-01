# typed: true
# frozen_string_literal: true

module Search
  class AzureModelResultView
    sig { returns T.nilable(GitHubModels::IModel) }
    attr_reader :model

    sig { returns T.nilable(String) }
    attr_reader :name, :publisher, :summary, :notes, :task, :rate_limit_tier, :description, :license,
      :license_description

    sig { returns T::Array[String] }
    attr_reader :categories, :supported_languages, :supported_input_modalities, :supported_output_modalities

    sig { returns T.nilable(Integer) }
    attr_reader :max_input_tokens, :max_output_tokens

    # Create a new AzureModelResultView from a `azure_model` document hash
    # returned from the ElasticSearch index.
    #
    # hash - Document Hash returned by ElasticSearch
    #
    def initialize(hash)
      @id = hash["_id"]
      @model = hash["_model"] || GitHubModels.domain.models.find(id: @id)

      source = hash["_source"] || {}
      @name = source["name"]
      @publisher = source["publisher"]
      @summary = source["summary"]
      @notes = source["notes"]
      @categories = source["categories"]
      @supported_languages = source["supported_languages"]
      @supported_input_modalities = source["supported_input_modalities"]
      @supported_output_modalities = source["supported_output_modalities"]
      @task = source["task"]
      @rate_limit_tier = source["rate_limit_tier"]
      @max_output_tokens = source["max_output_tokens"]
      @max_input_tokens = source["max_input_tokens"]
      @description = source["description"]
      @license = source["license"]
      @license_description = source["license_description"]
    end

    TOOL_TYPE = "github_models"

    def tool_type
      TOOL_TYPE
    end

    # Public: Used by BlackbirdControllerMethods#populate_results_data for global search results, and
    # by Marketplace::Payloads::IndexHelper#listing_from_result_view for Marketplace search results.
    sig { returns(T.nilable(GitHubModels::Types::ModelListing)) }
    def for_frontend_rendering
      model = self.model
      return nil if model.nil?

      {
        type: "model", # keep in sync with `type` prop of `ModelListing` in ui/packages/marketplace-common/types.ts
        model_url: model.details_path,
        id: model.external_id.to_s,
        registry: model.registry.to_s,
        name: model.name.to_s,
        friendly_name: model.friendly_name.to_s,
        task: model.task.to_s,
        publisher: model.publisher.to_s,
        summary: model.summary.to_s,
        tags: model.tags,
        logo_url: model.logo_url,
        dark_mode_icon: model.dark_mode_icon,
        light_mode_icon: model.light_mode_icon,
        max_input_tokens: model.max_input_tokens.to_i,
        max_output_tokens: model.max_output_tokens.to_i,
      }
    end

    # Public: Return the listing name. The name may or may not contain
    # highlight tags, but either way it has been HTML escaped and is html_safe.
    #
    # Returns an HTML escaped name String.
    def hl_name
      @hl_name ||= hl_description("name.ngram", @name)
    end

    # Public: Return the listing short_description. The short_description may or may not contain
    # highlight tags, but either way it has been HTML escaped and is html_safe.
    #
    # Returns an HTML escaped short_description String.
    def hl_short_description
      @hl_short_description ||= hl_description("summary", @summary)
    end

    # Returns true if there are highlight fragments for this listing. The
    # highlight fragments contain text from the various listing fields with the
    # relevant search terms surrounded by <em> tags.
    def highlights?
      !@highlights.nil?
    end

    private

    def hl_description(key, value)
      if highlights? && @highlights.key?(key)
        GitHub::Goomba::HighlightedSearchResultPipeline.to_html(@highlights[key].first)
      else
        formatted = GitHub::Goomba::ModelsMarkdownPipeline.to_html(value.to_s)
        HTMLTruncator.new(formatted, 350).to_html(wrap: false)
      end
    end
  end
end
