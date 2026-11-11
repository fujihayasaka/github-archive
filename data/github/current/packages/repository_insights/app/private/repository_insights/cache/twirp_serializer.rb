# typed: strict
# frozen_string_literal: true

module RepositoryInsights
  module Cache
    class TwirpSerializer
      extend T::Generic
      extend GitHub::RemoteCache::Serializer

      SourceValueType = type_template { { fixed: MonolithTwirp::ReposInsights::ReposInsights::V1::GetRepoTrafficResponse } }

      sig { override.params(object: SourceValueType).returns(Object) }
      def self.serialize(object)
        MonolithTwirp::ReposInsights::ReposInsights::V1::GetRepoTrafficResponse.encode_json(object)
      end

      sig { override.params(cache_value: Object).returns(SourceValueType) }
      def self.deserialize(cache_value)
        MonolithTwirp::ReposInsights::ReposInsights::V1::GetRepoTrafficResponse.decode_json(cache_value)
      end
    end
  end
end
