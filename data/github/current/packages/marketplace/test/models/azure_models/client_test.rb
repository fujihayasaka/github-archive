# typed: true
# frozen_string_literal: true

require "test_helper"

class AzureModels::ClientTest < GitHub::TestCase
  setup do
    @successful_azure_models_response = Faraday::Response.new(
      status: 200,
      body: [
        {
          id: "azureml://registries/HuggingFace/models/mistralai-mixtral-8x22b-instruct-v0.1/versions/4",
          model_registry: "HuggingFace",
          name: "mistralai-mixtral-8x22b-instruct-v0.1",
          friendly_name: "Mistral Instruct",
          task: "text-generation",
          publisher: "huggingface",
          license: "apache-2.0",
          description: "`mistralai/Mixtral-8x22B-Instruct-v0.1` powered by Text Generation Inference. ...",
          summary: "A really short description of Mixtral 8x22B Instruct v0.1.",
          model_family: "mistralai",
          model_version: 4,
          tags: ["all-purpose"],
        },
        {
          id: "azureml://registries/HuggingFace/models/cohereforai-c4ai-command-r-plus/versions/4",
          model_registry: "HuggingFace",
          name: "cohereforai-c4ai-command-r-plus",
          friendly_name: "Command R+",
          task: "text-generation",
          publisher: "huggingface",
          license: "cc-by-nc-4.0",
          description: "`CohereForAI/c4ai-command-r-plus` powered by Text Generation Inference. ...",
          summary: "A really short description of Command R+.",
          model_family: "CohereForAI",
          model_version: 4,
          tags: ["code"],
        },
      ].to_json
    )

    @successful_azure_models_response_v2 = Faraday::Response.new(
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
          license: nil,
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
          license: nil,
          tradeRestricted: true
        }]
      }.to_json
    )

    @successful_azure_model_details_response = Faraday::Response.new(
      status: 200,
      body: {
        id: "model-name-and-version-go-here",
        name: "cool-model",
        friendly_name: "Cool Model",
        task: "chat-completion",
        publisher: "cool-publisher",
        license: "mit",
        description: "A very cool model",
        samples: {
          "inputs": [
            {
              "messages": [
                {
                  "role": "user",
                  "content": "sample message"
                }
              ]
            }
          ]
        },
        summary: "A short model description",
        model_family: "some-model-family",
        notes: "Trustworthy!",
        model_version: 1,
        tags: ["reasoning"],
        properties: {
          "limits": {
            "rate": {
              "model_class": "high",
            },
            "languages": ["en"],
            "inputs": {
              "tokens": 100,
            },
            "outputs": {
              "tokens": 120,
            },
          },
          "training_data": "Jan 2024"
        },
        evaluation: "",
        license_description: "",
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
  end

  context "AzureModels::Client#fetch_models" do
    test "raises an error when the call to Azure fails" do
      # Make the external call fail
      GitHub::FaradayClient::External.any_instance
                                     .expects(:get)
                                     .returns(Faraday::Response.new(status: 500))

      assert_raises(AzureModels::Client::ApiError) { AzureModels::Client.fetch_models }
    end

    test "parses out the expected values correctly" do
      GitHub::FaradayClient::External.any_instance
                                     .expects(:get)
                                     .returns(@successful_azure_models_response)

      response = AzureModels::Client.fetch_models
      assert_equal response.size, 2

      # Assert that the important values have been parsed out properly
      model = T.must(response.first)

      assert_equal model[:id], "azureml://registries/HuggingFace/models/mistralai-mixtral-8x22b-instruct-v0.1/versions/4"
      assert_equal model[:registry], "HuggingFace"
      assert_equal model[:name], "mistralai-mixtral-8x22b-instruct-v0-1"
      assert_equal model[:original_name], "mistralai-mixtral-8x22b-instruct-v0.1"
      assert_equal model[:friendly_name], "Mistral Instruct"
      assert_equal model[:task], "text-generation"
      assert_equal model[:publisher], "huggingface"
      assert_equal model[:license], "apache-2.0"
      assert_equal model[:description], "`mistralai/Mixtral-8x22B-Instruct-v0.1` powered by Text Generation Inference. ..."
      assert_nil model[:samples]
      assert_equal model[:summary], "A really short description of Mixtral 8x22B Instruct v0.1."
      assert_equal model[:model_family], "mistralai"
      assert_equal model[:model_version], 4
      assert_equal model[:tags], ["all-purpose"]
    end
  end

  context "AzureModels::Client#fetch_models_v2" do
    test "raises an error when the call to Azure fails" do
      # Make the external call fail
      GitHub::FaradayClient::External.any_instance
                                     .expects(:post)
                                     .returns(Faraday::Response.new(status: 500))

      assert_raises(AzureModels::Client::ApiError) { AzureModels::Client.fetch_models_v2 }
    end

    test "parses out the expected values correctly" do
      GitHub::FaradayClient::External.any_instance
                                     .expects(:post)
                                     .returns(@successful_azure_models_response_v2)

      response = AzureModels::Client.fetch_models_v2
      assert_equal response.size, 2

      # Assert that the important values have been parsed out properly
      # Also that it's sorted alphabetically by friendly_name
      model = T.must(response.first)

      assert_equal model[:id], "azureml://registries/azureml-cohere/models/Cohere-embed-v3-multilingual/versions/3"
      assert_equal model[:registry], "azureml-cohere"
      assert_equal model[:name], "Cohere-embed-v3-multilingual"
      assert_equal model[:original_name], "Cohere-embed-v3-multilingual"
      assert_equal model[:friendly_name], "Cohere Embed v3 Multilingual"
      assert_equal model[:task], "embeddings"
      assert_equal model[:publisher], "cohere"
      assert_nil model[:license] # TODO: double check with Azure
      assert_equal model[:description], ""
      assert_nil model[:samples]
      assert_equal model[:summary], "A really short summary of Cohere Embed Multilingual."
      assert_equal model[:model_family], "cohere"
      assert_equal model[:model_version], 3
      assert_empty model[:tags]
    end
  end

  context "AzureModels::Client#fetch_model_details" do
    test "raises an error when call to Azure fails" do
      # Make the external call fail
      GitHub::FaradayClient::External.any_instance
                                     .expects(:get)
                                     .returns(Faraday::Response.new(status: 500))

      assert_raises(AzureModels::Client::ApiError) { AzureModels::Client.fetch_model_details(registry: "azureml-meta", model: "Llama-2-7b") }
    end

    test "parses out the expected values into a single Model correctly" do
      GitHub::FaradayClient::External.any_instance
                                     .expects(:get)
                                     .returns(@successful_azure_model_details_response)

      response = AzureModels::Client.fetch_model_details(registry: "azureml-meta", model: "Llama-2-7b")
      assert response

      # Assert that the important values have been parsed out properly
      model = T.must(response)
      assert_equal model[:id], "model-name-and-version-go-here"
      assert_equal model[:registry], "azureml-meta"
      assert_equal model[:name], "cool-model"
      assert_equal model[:friendly_name], "Cool Model"
      assert_equal model[:task], "chat-completion"
      assert_equal model[:publisher], "cool-publisher"
      assert_equal model[:license], "mit"
      assert_equal model[:description], "A very cool model"
      assert_equal model[:notes], "Trustworthy!"
      assert_equal model[:samples][:inputs], [{ "messages" => [{ "role" => "user", "content" => "sample message" }] }]
      assert_equal model[:summary], "A short model description"
      assert_equal model[:model_family], "some-model-family"
      assert_equal model[:model_version], 1
      assert_equal model[:tags], ["reasoning"]
      assert_equal model[:rate_limit_tier], "high"
      assert_equal model[:supported_languages], ["en"]
      assert_equal model[:max_input_tokens], 100
      assert_equal model[:max_output_tokens], 120
      assert_equal model[:training_data_date], "Jan 2024"
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
