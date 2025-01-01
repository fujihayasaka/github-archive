# typed: strict
# frozen_string_literal: true

module Copilot
  module Instrumenter
    extend T::Sig

    extend Copilot::Instrumentation::Business
    extend Copilot::Instrumentation::Individuals
  end
end
