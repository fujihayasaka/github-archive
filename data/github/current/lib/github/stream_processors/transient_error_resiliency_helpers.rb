# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module TransientErrorResiliencyHelpers
      STATEMENT_INVALID_CONDITIONS = proc do |error|
        error.message.match(/vttablet: Connection Closed|connection timed out|is either down or nonexistent|connect: connection refused|unable to connect|Max connect timeout reached|primary is not serving, there is a reparent operation in progress/i)
      end

      TRANSIENT_ERRORS_TO_RETRY_ON = {
        ActiveRecord::StatementInvalid => STATEMENT_INVALID_CONDITIONS,
        ActiveRecord::ConnectionFailed => proc { true },
        ::Redis::TimeoutError => proc { true },
        ::Redis::CannotConnectError => proc { true },
      }.freeze

      TRANSIENT_ERRORS_TO_PAUSE_ON = TRANSIENT_ERRORS_TO_RETRY_ON.merge(
        ActiveRecord::StatementInvalid => proc do |error|
          error.cause.is_a?(Resilient::Trilogy::CircuitOpenError) ||
            STATEMENT_INVALID_CONDITIONS.call(error)
        end,
        WaitForReplication::DataUnavailable => proc { true },
        Freno::Throttler::WaitedTooLong => proc { true },
        Freno::Throttler::CircuitOpen => proc { true },
        ElastomerClient::Client::ServerError => proc { true },
      ).freeze

      sig { params(error: T.any(StandardError, Exception)).returns(T::Boolean) }
      private def pause_on_transient_errors?(error)
        TRANSIENT_ERRORS_TO_PAUSE_ON.any? { |error_class, proc| error.is_a?(error_class) && proc.call(error) }
      end
      alias :transient_error? :pause_on_transient_errors?
    end
  end
end
