# typed: true
# frozen_string_literal: true

require "test_helper"

class AzureModels::ClientTest < GitHub::TestCase
  setup do
    @successful_azure_models_response = Faraday::Response.new(
      status: 200,
      body: {
        totalCount: 24,
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

    @successful_model_schema_response = Faraday::Response.new(
      status: 200,
      body: [
        {
          "config": {
            "examples": [
              {
                "chatHistory": [
                  {
                    "role": "user",
                    "content": "I am going to Paris, what should I see?"
                  },
                  {
                    "role": "assistant",
                    "content": "Paris, the capital of France, is known for its stunning architecture, art museums, historical landmarks, and romantic atmosphere. Here are some of the top attractions to see in Paris:\n\n1. The Eiffel Tower: The iconic Eiffel Tower is one of the most recognizable landmarks in the world and offers breathtaking views of the city.\n2. The Louvre Museum: The Louvre is one of the world's largest and most famous museums, housing an impressive collection of art and artifacts, including the Mona Lisa.\n3. Notre-Dame Cathedral: This beautiful cathedral is one of the most famous landmarks in Paris and is known for its Gothic architecture and stunning stained glass windows.\n\nThese are just a few of the many attractions that Paris has to offer. With so much to see and do, it's no wonder that Paris is one of the most popular tourist destinations in the world."
                  },
                  {
                    "role": "user",
                    "content": "What is so great about #1?"
                  }
                ]
              }
            ],
            "sampleInputs": [
              {
                "messages": [
                  {
                    "role": "user",
                    "content": "What is the history of the Great Wall of China?"
                  }
                ]
              },
              {
                "messages": [
                  {
                    "role": "user",
                    "content": "Can you explain the concept of time dilation in physics?"
                  }
                ]
              },
              {
                "messages": [
                  {
                    "role": "user",
                    "content": "What are some popular tourist attractions in Paris?"
                  }
                ]
              },
            ],
            "inputs": [
              {
                "key": "chatHistory",
                "friendlyName": "Chat History",
                "type": "array",
                "payloadPath": "messages",
                "required": true
              }
            ],
            "outputs": [
              {
                "key": "choices",
                "friendlyName": "Result",
                "type": "array",
                "payloadPath": "choices"
              }
            ],
            "fixedParameters": [],
            "parameters": [
              {
                "key": "max_tokens",
                "type": "integer",
                "payloadPath": "max_tokens",
                "default": 256,
                "min": 1,
                "max": 131072,
                "required": true
              },
              {
                "key": "temperature",
                "type": "number",
                "payloadPath": "temperature",
                "default": 1,
                "max": 1,
                "min": 0,
                "required": false
              },
              {
                "key": "top_p",
                "type": "number",
                "payloadPath": "top_p",
                "default": 1,
                "max": 1,
                "min": 0,
                "required": false
              },
              {
                "key": "stop",
                "type": "array",
                "payloadPath": "stop",
                "default": [],
                "required": false
              }
            ],
            "type": "Chat",
            "version": "0.1",
            "behavior": "OAILikeChat",
            "capabilities": {
              "bringYourOwnData": true,
              "systemPrompt": true
            }
          },
          "date": "1970-01-01T00:00:00.000Z"
        }
      ].to_json
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

  context "AzureModels::Client#fetch_models" do
    test "raises an error when the call to Azure fails" do
      # Make the external call fail
      GitHub::FaradayClient::External.any_instance
        .expects(:post)
        .returns(Faraday::Response.new(status: 500))

      assert_raises(AzureModels::Client::ApiError) { AzureModels::Client.fetch_models }
    end

    test "raises an error when the response from Azure Models endpoint is not valid JSON" do
      GitHub::FaradayClient::External.any_instance
        .expects(:post)
        .returns(Faraday::Response.new(status: 200, body: "this is not json"))

      GitHub::FaradayClient::External.any_instance
        .expects(:get)
        .with(AzureModels::Client::PUBLISHERS_ENDPOINT)
        .returns(Faraday::Response.new(status: 200, body: {}.to_json))

      assert_raises(AzureModels::Client::ApiError) { AzureModels::Client.fetch_models }
    end

    test "Properly parses the model data when the publisher data is invalid json" do
      GitHub::FaradayClient::External.any_instance
        .expects(:post)
        .returns(@successful_azure_models_response)

      GitHub::FaradayClient::External.any_instance
        .expects(:get)
        .with(AzureModels::Client::PUBLISHERS_ENDPOINT)
        .returns(Faraday::Response.new(status: 200, body: "this is not json"))

      models = AzureModels::Client.fetch_models
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
        .with(AzureModels::Client::PUBLISHERS_ENDPOINT)
        .returns(Faraday::Response.new(status: 200, body: "this is not json"))

      GitHub.logger.expects(:error).with(AzureModels::Client::PUBLISHERS_CALL_ERROR_MESSAGE, anything)
      GitHub::Chatterbox.client.expects(:say!).with("#github-models-ops", anything)
      GitHub.dogstats.expects(:increment).with("github_models.catalog_sync_failure", tags: ["publisher_data:true"])

      AzureModels::Client.fetch_models
    end

    test "parses out the expected values correctly" do
      GitHub::FaradayClient::External.any_instance
        .expects(:post)
        .with(AzureModels::Client::MODELS_ENDPOINT, anything)
        .returns(@successful_azure_models_response)

      GitHub::FaradayClient::External.any_instance
        .expects(:get)
        .with(AzureModels::Client::PUBLISHERS_ENDPOINT)
        .returns(@successful_model_publisher_response)

      response = AzureModels::Client.fetch_models
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
      assert_equal "cohere", model[:model_family]
      assert_equal "3", model[:model_version]
      assert_equal "darkbWwgdmVy...", model[:dark_mode_icon]
      assert_equal "lightbWwgdmVy...", model[:light_mode_icon]
      assert_empty model[:tags]
    end
  end

  context "AzureModels::Client#fetch_model_details" do
    test "raises an error when call to Azure fails" do
      # Make the external call fail
      GitHub::FaradayClient::External.any_instance
        .expects(:get)
        .returns(Faraday::Response.new(status: 500))

      assert_raises(AzureModels::Client::ApiError) do
        AzureModels::Client.fetch_model_details(registry: "azureml-meta", model: "Llama-2-7b", version: "1")
      end
    end

    test "raises an error when the call to Azure returns invalid json" do
      GitHub::FaradayClient::External.any_instance
        .expects(:get)
        .returns(Faraday::Response.new(status: 200, body: "this is not json"))

      assert_raises(AzureModels::Client::ApiError) do
        AzureModels::Client.fetch_model_details(registry: "azureml-meta", model: "Llama-2-7b", version: "1")
      end
    end

    test "parses out the expected values into a single Model correctly" do
      GitHub::FaradayClient::External.any_instance
        .expects(:get)
        .returns(@successful_azure_model_details_response)

      response = AzureModels::Client.fetch_model_details(registry: "azureml-meta", model: "Llama-2-7b", version: "1")
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
      assert_equal "cool-publisher", model[:model_family]
      assert_equal "1", model[:model_version]
      assert_equal ["reasoning"], model[:tags]
      assert_equal "high", model[:rate_limit_tier]
      assert_equal ["en"], model[:supported_languages]
      assert_equal 131072, model[:max_input_tokens]
      assert_equal 4096, model[:max_output_tokens]
      assert_equal "Jan 2024", model[:training_data_date]
    end
  end

  context "AzureModels::Client#fetch_model_schema" do
    test "raises when call to Azure fails" do
      # Make the external call fail
      GitHub::FaradayClient::External.any_instance
        .expects(:get)
        .returns(Faraday::Response.new(status: 500))

      assert_raises(AzureModels::Client::ApiError) { AzureModels::Client.fetch_model_schema(registry: "azureml-cohere", model: "cohere-command-r-plus") }
    end

    test "raises an error when the call to Azure returns invalid json" do
      GitHub::FaradayClient::External.any_instance
        .expects(:get)
        .returns(Faraday::Response.new(status: 200, body: "this is not json"))

      assert_raises(AzureModels::Client::ApiError) do
        AzureModels::Client.fetch_model_schema(registry: "azureml-cohere", model: "cohere-command-r-plus")
      end
    end

    test "parses out the expected values into a AzureModels::ModelSchema correctly" do
      GitHub::FaradayClient::External.any_instance
        .expects(:get)
        .returns(@successful_model_schema_response)

      response = AzureModels::Client.fetch_model_schema(registry: "azureml-cohere", model: "cohere-command-r-plus")
      assert response

      # Assert the top-level schema values
      schema = T.must(response)
      assert schema[:examples]
      assert schema[:sampleInputs]
      assert schema[:inputs]
      assert schema[:outputs]
      assert schema[:fixedParameters]
      assert schema[:capabilities]
      assert schema[:type]
      assert schema[:version]
      assert schema[:behavior]
      assert schema[:parameters]
    end
  end
end
