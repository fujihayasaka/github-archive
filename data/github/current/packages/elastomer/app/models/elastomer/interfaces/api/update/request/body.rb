# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Update
        module Request
          # A struct representing the possible body attributes passed into an update method. Here is an example
          # of default usage:
          #
          #   update(Body.new(doc: { foo: "bar" }), <Params>)
          #
          # See https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-update.html for more detail.
          class Body < T::Struct
            # One or both of `doc` and `script` is required
            prop :doc, T.nilable(T::Hash[Symbol, T.untyped])
            prop :script, T.nilable(Api::Request::Script)

            # Optional

            # Defaults to true
            prop :detect_noop, T.nilable(T::Boolean)
            # Defaults to false
            prop :doc_as_upsert, T.nilable(T::Boolean)
            # Defaults to false
            prop :scripted_upsert, T.nilable(T::Boolean)
            prop :upsert, T.nilable(T::Hash[Symbol, T.untyped])

            sig { returns(T::Hash[Symbol, T.untyped]) }
            def to_hash
              {
                doc:,
                doc_as_upsert:,
                script: script&.to_hash,
                scripted_upsert:,
                upsert:,
                detect_noop:,
              }.compact
            end
          end
        end
      end
    end
  end
end
