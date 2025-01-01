# typed: true
# frozen_string_literal: true

class Devtools::CodeUsageComponent < ApplicationComponent
  def initialize(code_usage)
    @code_usage = code_usage
  end
end
