# typed: true
# frozen_string_literal: true

require "test_helper"

class GitHubModels::ClientTest < GitHub::TestCase
  setup do
    @successful_azure_models_response = Faraday::Response.new(
      status: 200,
      body: {
        totalCount: 3,
        continuationToken: nil,
        summaries: [{
          inferenceTasks: ["embeddings"],
          fineTuningTasks: [],
          keywords: nil,
          popularity: 1.0,
          assetId: "azureml://registries/azureml-cohere/models/Cohere-embed-v3-multilingual/versions/3",
          name: "Cohere-embed-v3-multilingual",
          displayName: "Cohere Embed v3 Multilingual",
          version: "3",
          registryName: "azureml-cohere",
          publisher: "cohere",
          labels: ["latest"],
          summary: "A really short summary of Cohere Embed Multilingual.",
          createdTime: "2024-04-04T02:38:36.4088459+00:00",
          license: "custom",
          tradeRestricted: true
        },
        {
          inferenceTasks: ["chat-completion"],
          fineTuningTasks: [],
          keywords: nil,
          popularity: 1.0,
          assetId: "azureml://registries/azureml-mistral/models/Mistral-small/versions/1",
          name: "Mistral-small",
          displayName: "Mistral Small",
          version: "1",
          registryName: "azureml-mistral",
          publisher: "mistralai",
          labels: ["latest"],
          summary: "A really short summary of Mistral Small.",
          createdTime: "2024-05-03T18:45:01.4637035+00:00",
          license: "custom",
          tradeRestricted: true
        }]
      }.to_json
    )

    @successful_azure_models_response_with_continuation = Faraday::Response.new(
      status: 200,
      body: {
        totalCount: 3,
        continuationToken: "next-page-token",
        summaries: [{
          inferenceTasks: ["chat-completion"],
          fineTuningTasks: [],
          keywords: nil,
          popularity: 1.0,
          assetId: "azureml://registries/azureml/models/Phi-3-medium-4k-instruct/versions/5",
          name: "Phi-3-medium-4k-instruct",
          displayName: "Phi-3-medium instruct (4k)",
          version: "5",
          registryName: "azureml",
          publisher: "Microsoft",
          labels: ["latest"],
          summary: "A 14B parameters model, proves better quality than Phi-3-mini, with a focus on high-quality, reasoning-dense data.",
          createdTime: "2025-01-03T18:45:01.4637035+00:00",
          license: "mit",
          tradeRestricted: true
        }]
      }.to_json
    )

    @successful_azure_model_details_response = Faraday::Response.new(
      status: 200,
      body: {
        evaluation: "",
        notes: "Trustworthy!",
        trainingDataDate: "2024-01-20T00:00:00+00:00",
        playgroundLimits: {
          rateLimitTier: "high",
        },
        modelLimits: {
          textLimits: {
            inputContextWindow: 131072,
            maxOutputTokens: 4096,
          },
          supportedLanguages: ["en"],
        },
        inferenceTasks: ["chat-completion"],
        fineTuningTasks: [],
        keywords: ["reasoning"],
        licenseDescription: "",
        description: "A very cool model",
        assetId: "model-name-and-version-go-here",
        name: "cool-model",
        displayName: "Cool Model",
        version: "1",
        registryName: "azureml-meta",
        publisher: "cool-publisher",
        labels: ["latest"],
        summary: "A short model description",
        createdTime: "2024-07-19T22:29:02.1347264+00:00",
        license: "mit",
        tradeRestricted: true,
      }.to_json
    )

    @successful_azure_model_details_response_multimodal = Faraday::Response.new(
      status: 200,
      body: {
        evaluation: "",
        notes: "Trustworthy!",
        trainingDataDate: "2024-01-20T00:00:00+00:00",
        playgroundLimits: {
          rateLimitTier: "high",
        },
        modelLimits: {
          textLimits: {
            inputContextWindow: 131072,
            maxOutputTokens: 4096,
          },
          # Disable Rubocop so we can have a deliberate leading space
          supportedInputModalities: ["text", " image"], # rubocop:disable Style/WordArray
          supportedOutputModalities: ["text ", "image"], # rubocop:disable Style/WordArray
          supportedLanguages: ["en"],
        },
        inferenceTasks: ["chat-completion"],
        fineTuningTasks: [],
        keywords: ["reasoning"],
        licenseDescription: "",
        description: "A very cool model",
        assetId: "model-name-and-version-go-here",
        name: "cool-model",
        displayName: "Cool Model",
        version: "1",
        registryName: "azureml-meta",
        publisher: "cool-publisher",
        labels: ["latest"],
        summary: "A short model description",
        createdTime: "2024-07-19T22:29:02.1347264+00:00",
        license: "mit",
        tradeRestricted: true,
      }.to_json
    )

    @successful_model_publisher_response = Faraday::Response.new(
      status: 200,
      "body": {
        "value": [
          {
            "publisherName": "cohere",
            "displayName": "Cohere",
            "iconLight": "lightbWwgdmVy...",
            "iconDark": "darkbWwgdmVy...",
            "isPublic": true,
            "allowedTenants": nil
          },
          {
            "publisherName": "Core42",
            "displayName": "Core42",
            "iconLight": "PD94bWwgdm...",
            "iconDark": "PD94bWwgdm...",
            "isPublic": true,
            "allowedTenants": nil
          },
        ]
      }.to_json
    )
  end

  context "GitHubModels::Client#fetch_models" do
    test "raises an error when the call to Azure fails" do
      # Make the external call fail
      GitHub::FaradayClient::External.any_instance
        .expects(:post)
        .returns(Faraday::Response.new(status: 500))

      assert_raises(GitHubModels::Client::ApiError) { GitHubModels::Client.fetch_models }
    end

    test "raises an error when the response from Azure Models endpoint is not valid JSON" do
      GitHub::FaradayClient::External.any_instance
        .expects(:post)
        .returns(Faraday::Response.new(status: 200, body: "this is not json"))

      assert_raises(GitHubModels::Client::ApiError) { GitHubModels::Client.fetch_models }
    end

    test "Properly parses the model data when the publisher data is invalid json" do
      GitHub::FaradayClient::External.any_instance
        .expects(:post)
        .returns(@successful_azure_models_response)

      GitHub::FaradayClient::External.any_instance
        .expects(:get)
        .with(GitHubModels::Client::PUBLISHERS_ENDPOINT)
        .returns(Faraday::Response.new(status: 200, body: "this is not json"))

      models = GitHubModels::Client.fetch_models
      assert_equal models.size, 2

      last_model = T.must(models.last)
      # We didn't process the publisher data, so it should be nil
      refute last_model[:dark_mode_icon]
      # The rest of the model data should be there
      assert_equal "Mistral-small", last_model[:name]
    end

    test "logs the error when the publisher api returns incorrect json" do
      GitHub::FaradayClient::External.any_instance
        .expects(:post)
        .returns(@successful_azure_models_response)

      GitHub::FaradayClient::External.any_instance
        .expects(:get)
        .with(GitHubModels::Client::PUBLISHERS_ENDPOINT)
        .returns(Faraday::Response.new(status: 200, body: "this is not json"))

      GitHub.logger.expects(:error).with(GitHubModels::Client::PUBLISHERS_CALL_ERROR_MESSAGE, anything)
      GitHub::Chatterbox.client.expects(:say!).with("#github-models-ops", anything)
      GitHub.dogstats.expects(:increment).with("github_models.catalog_sync_failure", tags: ["publisher_data:true"])

      GitHubModels::Client.fetch_models
    end

    test "parses out the expected values correctly" do
      GitHub::FaradayClient::External.any_instance
        .expects(:post)
        .with(GitHubModels::Client::MODELS_ENDPOINT, anything)
        .returns(@successful_azure_models_response)

      GitHub::FaradayClient::External.any_instance
        .expects(:get)
        .with(GitHubModels::Client::PUBLISHERS_ENDPOINT)
        .returns(@successful_model_publisher_response)

      response = GitHubModels::Client.fetch_models
      assert_equal 2, response.size

      # Assert that the important values have been parsed out properly
      # Also that it's sorted alphabetically by friendly_name
      model = T.must(response.first)

      assert_equal "azureml://registries/azureml-cohere/models/Cohere-embed-v3-multilingual/versions/3", model[:id]
      assert_equal "azureml-cohere", model[:registry]
      assert_equal "Cohere-embed-v3-multilingual", model[:name]
      assert_equal "Cohere-embed-v3-multilingual", model[:original_name]
      assert_equal "Cohere Embed v3 Multilingual", model[:friendly_name]
      assert_equal "embeddings", model[:task]
      assert_equal "cohere", model[:publisher]
      assert_equal "custom", model[:license]
      assert_equal "", model[:description]
      assert_equal "A really short summary of Cohere Embed Multilingual.", model[:summary]
      assert_equal "3", model[:model_version]
      assert_equal "darkbWwgdmVy...", model[:dark_mode_icon]
      assert_equal "lightbWwgdmVy...", model[:light_mode_icon]
      assert_empty model[:tags]
    end

    test "fetches next page if continuation token is present in response" do
      GitHub::FaradayClient::External.any_instance
        .expects(:post)
        .with(GitHubModels::Client::MODELS_ENDPOINT, Not(includes("\"continuationToken\"")))
        .returns(@successful_azure_models_response_with_continuation) # Page 1 has 1 entries
        .once

      GitHub::FaradayClient::External.any_instance
        .expects(:post)
        .with(GitHubModels::Client::MODELS_ENDPOINT, includes("\"continuationToken\":\"next-page-token\""))
        .returns(@successful_azure_models_response) # Page 2 has 2 entries
        .once

      GitHub::FaradayClient::External.any_instance
        .expects(:get)
        .with(GitHubModels::Client::PUBLISHERS_ENDPOINT)
        .returns(@successful_model_publisher_response)

      response = GitHubModels::Client.fetch_models

      assert_equal 3, response.size
      assert_equal "Phi-3-medium-4k-instruct",  T.must(response.first)[:name]
      assert_equal "Cohere-embed-v3-multilingual",  T.must(response.second)[:name]
      assert_equal "Mistral-small",  T.must(response.third)[:name]
    end
  end

  context "GitHubModels::Client#fetch_model_details" do
    test "raises an error when call to Azure fails" do
      # Make the external call fail
      GitHub::FaradayClient::External.any_instance
        .expects(:get)
        .returns(Faraday::Response.new(status: 500))

      assert_raises(GitHubModels::Client::ApiError) do
        GitHubModels::Client.fetch_model_details(registry: "azureml-meta", model: "Llama-2-7b", version: "1")
      end
    end

    test "raises an error when the call to Azure returns invalid json" do
      GitHub::FaradayClient::External.any_instance
        .expects(:get)
        .returns(Faraday::Response.new(status: 200, body: "this is not json"))

      assert_raises(GitHubModels::Client::ApiError) do
        GitHubModels::Client.fetch_model_details(registry: "azureml-meta", model: "Llama-2-7b", version: "1")
      end
    end

    test "raises an error when model does not exist" do
      error = assert_raises(GitHubModels::Client::ApiError) do
        VCR.use_cassette("github_models/client_fetch_model_details_404") do
          GitHubModels::Client.fetch_model_details(registry: "azureml-meta", model: "NonExistentModel",
            version: "123")
        end
      end

      assert_includes error.message, "an error fetching the models from the Azure Models Service"
    end

    test "parses out the expected values into a single Model correctly" do
      GitHub::FaradayClient::External.any_instance
        .expects(:get)
        .returns(@successful_azure_model_details_response)

      response = GitHubModels::Client.fetch_model_details(registry: "azureml-meta", model: "Llama-2-7b", version: "1")
      assert response

      # Assert that the important values have been parsed out properly
      model = T.must(response)
      assert_equal "model-name-and-version-go-here", model[:id]
      assert_equal "azureml-meta", model[:registry]
      assert_equal "cool-model", model[:name]
      assert_equal "Cool Model", model[:friendly_name]
      assert_equal "chat-completion", model[:task]
      assert_equal "cool-publisher", model[:publisher]
      assert_equal "mit", model[:license]
      assert_equal "A very cool model", model[:description]
      assert_equal "Trustworthy!", model[:notes]
      assert_equal "A short model description", model[:summary]
      assert_equal "1", model[:model_version]
      assert_equal ["reasoning"], model[:tags]
      assert_equal "high", model[:rate_limit_tier]
      assert_equal ["en"], model[:supported_languages]
      assert_equal 131072, model[:max_input_tokens]
      assert_equal 4096, model[:max_output_tokens]
      assert_equal "Jan 2024", model[:training_data_date]
    end

    test "parses out the expected values, including modalities for multimodal models" do
      GitHub::FaradayClient::External.any_instance
        .expects(:get)
        .returns(@successful_azure_model_details_response_multimodal)

      response = GitHubModels::Client.fetch_model_details(registry: "azureml-meta", model: "Llama-2-7b", version: "1")
      assert response

      # Assert that the important values have been parsed out properly
      model = T.must(response)
      assert_equal "model-name-and-version-go-here", model[:id]
      assert_equal "azureml-meta", model[:registry]
      assert_equal "cool-model", model[:name]
      assert_equal "Cool Model", model[:friendly_name]
      assert_equal "chat-completion", model[:task]
      assert_equal "cool-publisher", model[:publisher]
      assert_equal "mit", model[:license]
      assert_equal "A very cool model", model[:description]
      assert_equal "Trustworthy!", model[:notes]
      assert_equal "A short model description", model[:summary]
      assert_equal "1", model[:model_version]
      assert_equal ["reasoning"], model[:tags]
      assert_equal "high", model[:rate_limit_tier]
      assert_equal ["en"], model[:supported_languages]
      assert_equal 131072, model[:max_input_tokens]
      assert_equal 4096, model[:max_output_tokens]
      assert_equal "Jan 2024", model[:training_data_date]
      assert_equal %w[text image], model[:supported_input_modalities]
      assert_equal %w[text image], model[:supported_output_modalities]
    end
  end

  context "GitHubModels::Client#fetch_model_schema" do
    test "raises when call to Azure fails" do
      # Make the external call fail
      GitHub::FaradayClient::External.any_instance
        .expects(:get)
        .returns(Faraday::Response.new(status: 500))

      assert_raises(GitHubModels::Client::ApiError) { GitHubModels::Client.fetch_model_schema(registry: "azureml-cohere", model: "cohere-command-r-plus") }
    end

    test "raises an error when model does not exist" do
      error = assert_raises(GitHubModels::Client::ApiError) do
        VCR.use_cassette("github_models/client_fetch_model_schema_404") do
          GitHubModels::Client.fetch_model_schema(registry: "azureml-cohere", model: "NonExistentModel")
        end
      end

      assert_includes error.message, "an error fetching the models from the Azure Models Service"
    end

    test "raises an error when the call to Azure returns invalid json" do
      GitHub::FaradayClient::External.any_instance
        .expects(:get)
        .returns(Faraday::Response.new(status: 200, body: "this is not json"))

      assert_raises(GitHubModels::Client::ApiError) do
        GitHubModels::Client.fetch_model_schema(registry: "azureml-cohere", model: "cohere-command-r-plus")
      end
    end

    test "parses out the expected values into a AzureModels::ModelSchema correctly" do
      response = VCR.use_cassette("github_models/client_fetch_model_schema") do
        GitHubModels::Client.fetch_model_schema(registry: "azureml-cohere", model: "cohere-command-r-plus")
      end

      refute_nil response

      # Assert the top-level schema values
      schema = T.must(response)
      refute_empty schema[:examples]
      refute_empty schema[:sampleInputs]
      refute_empty schema[:inputs]
      refute_empty schema[:outputs]
      refute_empty schema[:fixedParameters]
      refute_empty schema[:capabilities]
      assert_equal "Chat", schema[:type]
      assert_predicate schema[:version], :present?
      assert_predicate schema[:behavior], :present?
      refute_empty schema[:parameters]
    end
  end
end
