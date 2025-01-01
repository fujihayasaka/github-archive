# typed: true
# frozen_string_literal: true

module Elastomer
  module Mappings
    # An Elasticsearch mapping that is prepared to be used for creating an indexes or update their mapping.
    class GeneratedMapping < T::Struct
      # The mapping generated for Elasticsearch
      const :mapping, T::Hash[T.untyped, T.untyped]

      # The settings used to generate the mapping
      const :settings, T::Hash[T.untyped, T.untyped]

      # The computed version of the mapping encoded into the mapping using Elastomer::SearchIndexManager.version
      const :version, String
    end
  end
end
