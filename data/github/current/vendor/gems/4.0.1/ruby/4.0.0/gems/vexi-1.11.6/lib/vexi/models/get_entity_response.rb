# frozen_string_literal: true
#              


require "vexi/entity"

module Vexi
  # GetEntityResponse is the abstract base class for get entity response.
  class GetEntityResponse
    attr_reader :name
    attr_reader :entity
    attr_reader :error

    def initialize(name: "", entity: nil, error: nil)
      @name =      (name        )
      @entity =      (entity                   )
      @error =      (error                          )
    end
  end
end
