# typed: true
# frozen_string_literal: true

module CustomKeysHelper
  extend T::Helpers

  sig { params(provider: T.nilable(T.any(String, Symbol))).returns(String) }
  def pretty_custom_key_provider(provider)
    return "" unless provider

    case provider.to_s.downcase
    when "azureai" then "Azure AI"
    when "openai" then "OpenAI"
    else
      provider.to_s.humanize
    end
  end
end
