# typed: true
# frozen_string_literal: true

require "newsies/object"

module Newsies
  class List < ::Newsies::Object
    def self.to_id(object)
      Integer(object.id)
    end

    def initialize(type, id)
      super
      @id = Integer(@id)
    end
  end
end
