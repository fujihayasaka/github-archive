# typed: true
# frozen_string_literal: true

module GitHubModels
  class GettingStartedContent

    LANGUAGE_NAMES = {
      python: "Python",
      js: "JavaScript",
      csharp: "C#",
      java: "Java",
      rest: "REST"
    }

    CHAT_SDK_CONFIG = {
      azure: {
        name: "Azure AI Inference SDK",
        supported_languages: [:python, :js, :csharp, :java],
        supported_publishers: ["all"]
      },
      openai: {
        name: "OpenAI SDK",
        supported_languages: [:python, :js, :csharp],
        supported_publishers: ["OpenAI"]
      },
      curl: {
        name: "cURL",
        supported_languages: [:rest],
        supported_publishers: ["all"]
      },
      mistral: {
        name: "Mistral AI SDK",
        supported_languages: [:python, :js],
        supported_publishers: ["Mistral AI"]

      },
      cohere: {
        name: "Cohere AI SDK",
        supported_languages: [:python, :js],
        supported_publishers: ["Cohere"]
      }
    }

    EMBEDDINGS_SDK_CONFIG = {
      azure: {
        name: "Azure AI Inference SDK",
        supported_languages: [:python, :js],
        supported_publishers: ["all"]
      },
      openai: {
        name: "OpenAI SDK",
        supported_languages: [:python, :js, :csharp],
        supported_publishers: ["OpenAI"]
      },
      cohere: {
        name: "Cohere AI SDK",
        supported_languages: [:python, :js],
        supported_publishers: ["Cohere"]
      }
    }

    sig { params(model: GitHubModels::Types::Model, schema: T.nilable(GitHubModels::Types::ModelSchema)).returns(T::Hash[Symbol, T::untyped]) }
    def self.build_template_data(model, schema)
      model_name = model[:original_name]
      publisher_name = model[:publisherSlug]
      model_capabilities = GitHubModels::GettingStartedContent.get_model_capabilities(model, schema)
      lang_sdk_list = GitHubModels::GettingStartedContent.generate_lang_sdk_list(model)

      {
        model_name: model_name,
        publisher_name: publisher_name,
        model_capabilities: model_capabilities,
        lang_sdk_list: lang_sdk_list
      }
    end

    sig { params(model: GitHubModels::Types::Model).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def self.generate_lang_sdk_list(model)
      sdk_file_name = {
        curl: "curl",
        azure: "azure_sdk",
        openai: "openai_sdk",
        mistral: "mistral_sdk",
        cohere: "cohere_sdk"
      }

      result = []

      languages = [:python, :js, :csharp, :java, :rest]
      task = model[:task] == "embeddings" ? :embeddings : :chat
      sdk_config = task == :embeddings ? EMBEDDINGS_SDK_CONFIG : CHAT_SDK_CONFIG

      languages.each do |lang|
        supported_sdks = sdk_config.select { |_, config| config[:supported_languages].include?(lang) && (config[:supported_publishers].include?("all") || config[:supported_publishers].include?(model[:publisher])) }.keys
        sdks = supported_sdks.map do |sdk|
          {
            sdk: sdk,
            name: sdk_config[sdk][:name],
          }
        end

        result << {
          lang: lang,
          lang_name: LANGUAGE_NAMES[lang],
          sdks: sdks,
          task: task
        }
      end

      result
    end

    sig { params(model: GitHubModels::Types::Model, schema: T.nilable(GitHubModels::Types::ModelSchema)).returns(T::Hash[Symbol, T::untyped]) }
    def self.get_model_capabilities(model, schema)
      # Model capabilities determine what options to be shown in the getting started code samples.

      {
        top_p: schema&.dig(:parameters)&.any? { |param| param[:key] == "top_p" } || false,
        max_tokens: schema&.dig(:parameters)&.any? { |param| param[:key] == "max_tokens" } || false,
        temperature: schema&.dig(:parameters)&.any? { |param| param[:key] == "temperature" } || false,
        system_prompt: schema&.dig(:capabilities, :systemPrompt) || false
      }
    end
  end
end
