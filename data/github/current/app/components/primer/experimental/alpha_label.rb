# typed: true
# frozen_string_literal: true

module Primer
  module Experimental
    # The AlphaLabel component is a label component that inherits from Primer::Beta::Label.
    class AlphaLabel < Primer::Beta::Label
      # @param system_arguments [Hash] Additional system arguments.
      def initialize(**system_arguments)
        super(**system_arguments)
      end
    end
  end
end
