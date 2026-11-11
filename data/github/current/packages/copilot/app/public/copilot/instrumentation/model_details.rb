# typed: strict
# frozen_string_literal: true

module Copilot
  module Instrumentation::ModelDetails
    extend T::Helpers
    include Copilot::Signatures::Shared

    abstract!
  end
end
