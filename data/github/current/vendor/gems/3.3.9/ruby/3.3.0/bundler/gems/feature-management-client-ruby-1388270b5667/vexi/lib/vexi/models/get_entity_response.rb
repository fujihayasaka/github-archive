# frozen_string_literal: true
# typed: strict

require "sorbet-runtime"
require "vexi/entity"

module Vexi
  # GetEntityResponse is the abstract base class for get entity response.
  class GetEntityResponse
    attr_reader :name
    attr_reader :entity
    attr_reader :error

    def initialize(name: "", entity: nil, error: nil)
      @name = T.let(name, String)
      @entity = T.let(entity, T.nilable(Entity))
      @error = T.let(error, T.nilable(StandardError))
    end
  end
end
