# typed: true
# frozen_string_literal: true

module CopilotByok
  module ProviderData
    module CustomKey
      class AwsBedrock < T::Struct
        prop :region, String

        sig { params(data_hash: T::Hash[String, T.untyped]).returns(AwsBedrock) }
        def self.build!(data_hash)
          region = data_hash["region"]
          raise Error.new("region is required") if region.nil?

          new(region: region)
        end

        sig { returns(T::Hash[String, T.untyped]) }
        def to_twirp_details
          { "region" => region }
        end
      end
    end
  end
end
