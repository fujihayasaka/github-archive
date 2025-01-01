# frozen_string_literal: true
#              

require "active_support"
require "active_support/notifications"
require "vexi/instrumenter"

module Vexi
  module Observability
    # Vexi null notifications instrumenter
    class Null
      include Instrumenter

      def instrument(_name, _payload = {}); end
    end
  end
end
