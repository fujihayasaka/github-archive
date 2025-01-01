# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Request
        # A struct representing the possible `script` properties in an Elasticsearch request.
        #
        # USAGE:
        #
        #   Script.new(lang: Lang::Painless, source: "ctx._source.foo = 'bar'")
        #
        # See https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-scripting.html for more detail.
        class Script < T::Struct
          extend T::Sig
          prop :lang, T.nilable(Lang)
          prop :source, T.nilable(String)
          prop :id, T.nilable(String)
          prop :params, T.nilable(T::Hash[Symbol, T.untyped])

          sig { returns(T::Hash[Symbol, T.untyped]) }
          def to_hash
            {
              id:,
              lang: lang&.serialize,
              params:,
              source:,
            }.compact
          end
        end
      end
    end
  end
end
