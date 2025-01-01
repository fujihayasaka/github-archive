# typed: strict
# frozen_string_literal: true

module Platform
  module Objects
    class Base < GraphQL::Schema::Object
      module Deprecated
        extend T::Sig

        sig { params(new_name: String).returns(String) }
        def graphql_name(new_name = T.unsafe(nil)); end

        sig { returns(String) }
        def name; end
      end
    end
  end
end
