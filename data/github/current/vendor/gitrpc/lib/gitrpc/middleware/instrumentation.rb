# typed: true
# frozen_string_literal: true

module GitRPC
  class Middleware
    class Instrumentation
      def initialize(backend)
        @backend = backend
      end

      def call(meth, message, *args, **kwargs)
        ::GitRPC.instrument(:remote_call, :name => message, :args => args) do
          @backend.call(meth, message, *args, **kwargs)
        end
      end
    end
  end
end
