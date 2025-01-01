# typed: true
# frozen_string_literal: true

module Mocks
  class User
    attr_reader :id

    def initialize(id: 1)
      @id = id
    end
  end
end
