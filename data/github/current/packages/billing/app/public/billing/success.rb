# typed: strict
# frozen_string_literal: true

module Billing
  class Success < Billing::Response

    sig { params(content: T.untyped).void }
    def initialize(content)
      super(content: content, success: true)
    end
  end
end
