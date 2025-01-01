# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable::Processor
  module Result
    extend T::Helpers
    include Kernel
    sealed!

    class Success
      include Result
    end

    class Error
      include Result
    end

    class Skip
      include Result

      sig { returns(String) }
      attr_reader :reason

      sig { params(reason: String).void }
      def initialize(reason)
        @reason = reason
      end
    end

    sig { returns(String) }
    def serialize = self.class.name.demodulize.downcase
  end
end
