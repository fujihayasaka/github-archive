# typed: true
# frozen_string_literal: true

module ModelsByok::CustomKeysHelper
  extend T::Helpers

  sig { params(provider: T.nilable(T.any(String, Symbol))).returns(String) }
  def pretty_models_byok_custom_key_provider(provider)
    return "" unless provider

    case provider.to_s.downcase
    when "azureai" then "Microsoft Foundry"
    when "openai" then "OpenAI"
    else
      provider.to_s.humanize
    end
  end
end
