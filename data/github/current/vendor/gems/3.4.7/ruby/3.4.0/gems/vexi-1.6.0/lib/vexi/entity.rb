# frozen_string_literal: true
#              

module Vexi
    # Public: Vexi entity interface.
  module Entity
    attr_accessor :not_found

    def initialize
      @not_found =      (false            )
    end
  end
end
