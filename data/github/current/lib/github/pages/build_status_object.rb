# typed: true
# frozen_string_literal: true

module GitHub
  module Pages
    # Generic status object.
    class BuildStatusObject
      attr_accessor :status, :err, :out, :commit
      def initialize(status, err, out, commit = nil)
        @status = status
        @err = err
        @out = out
        @commit = commit
      end
    end
  end
end
