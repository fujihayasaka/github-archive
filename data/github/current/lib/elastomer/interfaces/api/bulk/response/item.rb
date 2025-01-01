# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Bulk
        module Response
          class Item < T::Struct
            extend T::Sig

            const :create, T.nilable(Response::ItemResult)
            const :delete, T.nilable(Response::ItemResult)
            const :index, T.nilable(Response::ItemResult)
            const :update, T.nilable(Response::ItemResult)

            sig { params(response: T::Hash[String, T::Hash[String, T.untyped]]).returns(Item) }
            def self.from_es_response(response)
              key, val = response.entries.first
              new(
                T.must(key).to_sym => Response::ItemResult.from_es_response(T.must(val))
              )
            end

            sig { returns(Response::ItemResult) }
            def item_result
              T.must(create || delete || index || update)
            end

            sig { returns(T::Hash[Symbol, T.untyped]) }
            def to_hash
              {
                create: create&.to_hash,
                delete: delete&.to_hash,
                index: index&.to_hash,
                update: update&.to_hash
              }.compact
            end
          end
        end
      end
    end
  end
end
