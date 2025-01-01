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

    def for_frontend_rendering
      json = AzureModels::CatalogItem.find(@id).value
      model = self.class.to_azure_model(JSON.parse(json)["model"], "")
      model[:type] = "model"
      model[:model_url] = model_url(model[:id])
      model
    end

    private

    def model_url(model_id)
      match_data = model_id.match(/azureml:\/\/registries\/(.*?)\/models\/(.*?)\/versions\/\d+/)
      "/marketplace/models/#{match_data[1].gsub(".", "-")}/#{match_data[2].gsub(".", "-")}"
    end
  end
end
