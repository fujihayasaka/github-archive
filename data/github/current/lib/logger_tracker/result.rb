# typed: true
# frozen_string_literal: true

class LoggerTracker
  class Result
    attr_reader :file, :lineno

    def initialize(file, lineno)
      @file   = file
      @lineno = lineno
    end

    def render
      "#{self.file}#L#{self.lineno}"
    end
  end
end
