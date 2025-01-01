# typed: true
# frozen_string_literal: true

module Coders
  class RescueErrors
    extend Forwardable
    def_delegator :@coder, :dump

    def initialize(coder = Identity.new, errors = [StandardError], &handler)
      @coder = coder
      @errors = errors
      @handler = handler || proc {}
    end

    def load(value)
      @coder.load(value)
    rescue *@errors => e
      @handler.call(e, value, @coder)
    end
  end
end
