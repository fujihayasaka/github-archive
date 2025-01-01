# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Middleware
    class EnsureValidCall
      def initialize(backend)
        @backend = backend
      end

      def call(meth, message, *args, **kwargs)
        unless GitRPC::Backend.rpc_call?(message)
          raise GitRPC::Failure.raise(NoMethodError.new("Undefined RPC call #{message}"))
        end

        @backend.call(meth, message, *args, **kwargs)
      end
    end
  end
end
