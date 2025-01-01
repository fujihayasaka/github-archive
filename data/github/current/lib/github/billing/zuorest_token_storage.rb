# typed: strict
# frozen_string_literal: true

require "zuorest"

class GitHub::Billing::ZuorestTokenStorage < Zuorest::TokenStorage
  sig { void }
  def initialize
    @tokens = T.let({}, T::Hash[String, T::Hash[T.untyped, T.untyped]])
  end

  sig { params(key: String).returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
  def get(key)
    result = Billing::Kv.store.get(key).value { nil }
    return unless result

    begin
      JSON.parse(result)
    rescue JSON::ParserError
      GitHub.logger.info(
        "unable to parse value stored in Billing::Kv, falling back to nil",
        "code.namespace": "GitHub::Billing::ZuorestTokenStorage",
        "code.function": "get",
        "gh.zuorest_token_storage.get.result": result,
      )
    end
  end

  sig { params(key: String, token_data: T::Hash[T.untyped, T.untyped]).void }
  def store(key, token_data)
    # Expire token stored one minute before the actual expiration time
    Billing::Kv::DataStore.with_write do
      Billing::Kv.store.set(key, token_data.to_json)
    end
  end
end
