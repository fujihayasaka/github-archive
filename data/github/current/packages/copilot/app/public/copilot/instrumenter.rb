# typed: strict
# frozen_string_literal: true

module Copilot
  module Instrumenter

    extend Copilot::Instrumentation::Business
    extend Copilot::Instrumentation::Individuals
    extend Copilot::Instrumentation::Limiter
  end
end
