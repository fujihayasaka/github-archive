# frozen_string_literal: true
# typed: strict

module Vexi
  # GetEntityResponse is the abstract base class for get entity response.
  class GetEntityResponse
    extend T::Sig

    sig { returns(String) }
    attr_reader :name

    sig { returns T.nilable(Entity) }
    attr_reader :entity

    sig { returns(T.nilable(StandardError)) }
    attr_reader :error

    sig { params(name: String, entity: T.nilable(Entity), error: T.nilable(StandardError)).void }
    def initialize(name: "", entity: nil, error: nil); end
  end
end
