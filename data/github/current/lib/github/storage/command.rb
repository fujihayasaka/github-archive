# typed: true
# frozen_string_literal: true

module GitHub::Storage
  class Command
    class NilOutput
      def printf(*args)
      end
    end

    class TestOutput
      attr_reader :msgs

      def initialize
        reset
      end

      def reset
        @msgs = []
      end

      def printf(msg, *args)
        @msgs << (msg.strip % args)
      end

      def contains?(partial_or_regex)
        @msgs.each do |m|
          return true if m[partial_or_regex]
        end
        false
      end

      def missing?(partial_or_regex)
        !contains?(partial_or_regex)
      end

      def empty?
        @msgs.empty?
      end
    end

    def initialize(log_io: nil, dry_run: false)
      @dry_run = dry_run
      @log_io = log_io || (
        ($stderr.tty? || $stdout.tty?) ? $stdout : NilOutput.new
      )
    end

    def perform
      raise NotImplementedError
    end

    private

    def dry_run?
      !!@dry_run
    end

    def log(message, *args)
      @log_io.printf("#{message}\n", *args)
    end
  end
end
