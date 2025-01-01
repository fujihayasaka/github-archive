# typed: strict
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    class Message
      extend Forwardable

      sig { params(consumer_message: Hydro::Consumer::ConsumerMessage, dead_letter_topic: T.nilable(String)).returns(Message) }
      def self.build(consumer_message, dead_letter_topic: nil)
        if dead_letter_topic.present? && consumer_message.topic =~ /#{Regexp.quote(dead_letter_topic)}\Z/
          new(DeadLetterUnwrapper.unwrap(consumer_message), dead_letter_message: consumer_message)
        else
          new(consumer_message)
        end
      end

      def_delegators :consumer_message, :headers, :id, :key, :offset, :partition, :schema, :source_message, :timestamp, :topic, :value

      # Public: The reason the message is in a skipped or error status
      # Returns String or Exception
      sig { returns(T.nilable(T.any(String, Symbol, Exception))) }
      attr_reader :cause

      sig do
        params(
          consumer_message: Hydro::Consumer::ConsumerMessage, dead_letter_message: T.nilable(Hydro::Consumer::ConsumerMessage)
        ).void
      end
      def initialize(consumer_message, dead_letter_message: nil)
        @consumer_message = consumer_message
        @dead_letter_message = dead_letter_message

        @cause = T.let(nil, T.nilable(T.any(String, Symbol, Exception)))
        @result = T.let(nil, T.nilable(Symbol))
        @skipped_process = T.let(nil, T.nilable(T::Boolean))
      end

      # Public: Mark a message as successful
      #
      # Returns nothing
      sig { void }
      def success
        @result = :success
      end

      # Public: Whether or not the message was successful
      #
      # Returns Boolean
      sig { returns(T::Boolean) }
      def success?
        !error? && !skipped?
      end

      # Public: Marks a message as failed due to an error
      #
      # cause - The Exception that caused the message to fail
      #
      # Returns nothing
      sig { params(cause: T.nilable(Exception)).void }
      def error(cause = nil)
        @result = :error
        @cause = cause
      end

      # Public: Whether or not the message failed due to an error
      #
      # Returns Boolean
      sig { returns(T::Boolean) }
      def error?
        @result == :error
      end

      # Public: Marks a message as skipped
      #
      # cause - The String reason for the message being skipped
      #
      # Returns nothing
      sig { params(cause: T.any(String, Symbol, NilClass)).void }
      def skip(cause = nil)
        @result = :skipped
        @cause = cause
      end

      # Public: Whether or not the message was skipped
      #
      # Returns Boolean
      sig { returns(T::Boolean) }
      def skipped?
        @result == :skipped
      end

      # Public: Skip marking the message as processed
      #
      # cause - The String reason for the message being skipped
      #
      # Returns nothing
      sig { void }
      def skip_process
        @skipped_process = true
      end

      # Public: Whether or not the message was processed
      #
      # Returns Boolean
      sig { returns(T::Boolean) }
      def processed?
        !@skipped_process
      end

      sig { returns(T::Boolean) }
      def dead_letter_message?
        dead_letter_message.present? &&
          !!(T.must(dead_letter_message).schema =~ /github\.v1\.DeadLetter\Z/)
      end

      sig { returns(Integer) }
      def retries
        return -1 unless dead_letter_message?
        T.must(dead_letter_message).value[:retries] || 0
      end

      sig { returns(T.nilable(String)) }
      def original_error_class
        dead_letter_message&.value[:error_class]
      end

      sig { returns(T::Hash[T.untyped, T.untyped]) }
      def envelope
        EnvelopeGenerator.new.generate(consumer_message)
      end

      sig { params(path: Symbol).returns(T.untyped) }
      def dig(*path)
        consumer_message.value.dig(*path)
      end

      private

      sig { returns(Hydro::Consumer::ConsumerMessage) }
      attr_reader :consumer_message

      sig { returns(T.nilable(Hydro::Consumer::ConsumerMessage)) }
      attr_reader :dead_letter_message
    end
  end
end
