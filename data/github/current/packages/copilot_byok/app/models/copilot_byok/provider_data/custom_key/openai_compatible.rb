# typed: true
# frozen_string_literal: true

module CopilotByok
  module ProviderData
    module CustomKey
      class OpenAICompatible < T::Struct
        prop :base_url, String

        sig { params(data_hash: T::Hash[String, T.untyped]).returns(OpenAICompatible) }
        def self.build!(data_hash)
          base_url = data_hash["base_url"]
          raise Error.new("base_url is required") if base_url.nil?

          new(base_url: base_url)
        end

        sig { returns(T::Hash[String, T.untyped]) }
        def to_twirp_details
          { "base_url" => base_url }
        end
      end
    end
  end
end
