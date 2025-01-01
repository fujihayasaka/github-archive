# typed: true
# frozen_string_literal: true

require_relative "bertrpc/promise"

module IOPromise
  module BERTRPC
    class << self
      def async_call(bert_mod, cmd, path, options, message, args, kwargs)
        if bert_mod.respond_to?(:build_action)
          bert_action = bert_mod.build_action(cmd, path, options, message, args, kwargs)
          ::IOPromise::BERTRPC::Promise.new(bert_action, options)
        else
          Promise.resolve.then do
            status, res = bert_mod.send_message(path, options, message, args, kwargs)
            if status == :ok
              res
            elsif status == :boom
              GitRPC::Failure.raise(res)
            else
              raise GitRPC::NetworkError, "invalid bertrpc status: #{status.inspect}"
            end
          end
        end
      end
    end
  end
end
