# typed: strong
# frozen_string_literal: true

# TODO: remove this when we upgrade GraphQL gem to 2.4
module GraphQL
  class Schema
    extend T::Sig

    sig { params(arg: T.untyped).void }
    def self.did_you_mean(arg); end
  end

  class InvalidNullError
    extend T::Sig

    sig { returns(GraphQL::Language::Nodes::Field) }
    def ast_node; end
  end
end
