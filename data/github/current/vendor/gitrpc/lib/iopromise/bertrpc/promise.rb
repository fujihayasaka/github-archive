# typed: true
# frozen_string_literal: true

require "iopromise"

require_relative "executor_pool"

module IOPromise
  module BERTRPC
    class Promise < ::IOPromise::Base
      attr_reader :bert_action, :bert_call_state, :operation_timeout

      def initialize(bert_action = nil, options = {})
        super()

        @bert_action = bert_action
        @bert_call_state = nil
        @iop_monitor = nil

        # use these defaults, we could potentially allow overriding them if needed
        @connect_timeout = options[:connect_timeout] || GitRPC.connect_timeout
        # match the fudge factor used by the plain bertrpc method, ensures we get a timeout from the server side where possible
        @operation_timeout = GitRPC::Timer.fudge(options[:timeout] || GitRPC.timeout, :client)
        @connect_expire = nil
        @operation_expire = nil

        # `.then {}` creates new instances of this class with default arguments,
        # so we revert to regular promise behaviour when this happens.
        unless @bert_action.nil?
          @bert_call_state = ::BERTRPC::MuxHandler::CallState.new
          @bert_call_state.on_complete do |result|
            fulfill(result)
            cleanup
          end
          @bert_call_state.on_error do |reason|
            reject(wrap_errors(reason))
            cleanup
          end

          ::IOPromise::ExecutorContext.current.register(self)
        end
      end

      def update_monitor
        return if @bert_call_state.nil?

        readfd, writefd = bert_call_state.select_fds

        interest = if writefd.nil?
          :r
        elsif readfd.nil?
          :w
        else
          :rw
        end

        if @iop_monitor.nil?
          io = readfd || writefd

          # we can't register a monitor without an io
          return if io.nil?

          @iop_monitor = ::IOPromise::ExecutorContext.current.register_observer_io(self, io, interest)
        else
          @iop_monitor.interests = interest
        end
      end

      def cleanup
        @iop_monitor.close unless @iop_monitor.nil?
      end

      def monitor_ready(monitor, readiness)
        begin
          bert_call_state.run
        rescue StandardError => e
          bert_call_state.error = e
        end
      end

      def wait
        if @bert_action.nil?
          super
        else
          ::IOPromise::ExecutorContext.current.wait_for_all_data(end_when_complete: self)
        end
      end

      def execute_pool
        ::IOPromise::BERTRPC::ExecutorPool.for(Thread.current)
      end

      def beginning
        super

        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @connect_expire = now + @connect_timeout if @connect_timeout
        @operation_expire = now + @operation_timeout if @operation_timeout
      end

      def wrap_errors(reason)
        reason.is_a?(Array) ? ::GitRPC::Failure.decode(reason) : reason
      end

      def timeout_remaining
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        expiration = if @bert_call_state.connected?
          @operation_expire
        else
          @connect_expire
        end

        return nil if expiration.nil?
        return 0 if now >= expiration
        expiration - now
      end

      def timeout?
        remaining = timeout_remaining
        return false if remaining.nil?
        remaining <= 0
      end

      def safe_pass_result
        call = bert_call_state

        if !call.connected?
          if !call.error.is_a?(::BERTRPC::BERTRPCError)
            new_error = ::BERTRPC::ConnectionError.new(call.host, call.port)
            new_error.original_exception = call.error
            call.error = new_error
          end
        elsif !call.finished?
          if !call.error.is_a?(::BERTRPC::BERTRPCError)
            new_error = ::BERTRPC::ReadTimeoutError.new(call.host, call.port, operation_timeout)
            new_error.original_exception = call.error
            call.error = new_error
          end
        else
          begin
            status, res = call.read_result
            if status == :ok
              call.result = res
            elsif status == :boom
              call.error = res
            else
              # Oops, we leaked GitRPC namespace into our fork of bertrpc where this copied from, oh well :)
              call.error = GitRPC::NetworkError.new("invalid bertrpc status: #{status.inspect}")
            end
          rescue StandardError => e
            call.error = e
          end
        end

        # we notify now, rather than automatically when we later resolve the promise.
        # this ensures that instrumentation doesn't accidentally include then handlers.
        notify_completion(value: bert_call_state.result, reason: wrap_errors(bert_call_state.error))
      end
    end
  end
end
