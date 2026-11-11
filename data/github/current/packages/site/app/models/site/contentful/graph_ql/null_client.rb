# typed: strict
# frozen_string_literal: true

module Site
  module Contentful
    module GraphQL
      class NullClient
        sig { params(_query: T.untyped, _options: T.untyped).returns(NullResponse) }
        def query(_query, **_options)
          NullResponse.new(data: nil, errors: ["NullClient: No data available. GraphQL client was not initialized."])
        end

        sig { params(_query: T.untyped).void }
        def parse(_query); end

        class NullResponse < T::Struct
          prop :data, T.nilable(T::Hash[T.untyped, T.untyped])
          prop :errors, T::Array[String]
        end
      end
    end
  end
end
