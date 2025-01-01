# typed: true
# frozen_string_literal: true

module Platform
  module Authorization
    class ExecutionLog
      attr_reader :status, :steps, :enabled
      attr_accessor :context

      def self.success; new(:success) end
      def self.failed; new(:failed) end

      def initialize(status)
        @status = status
        @steps = []
        @context = {}
        @enabled = false
      end

      sig { returns(T::Boolean) }
      def success?
        status == :success
      end

      sig { returns(T::Boolean) }
      def failed?
        !success?
      end

      sig { returns(T.self_type) }
      def enable!
        @enabled = true
        self
      end

      sig { returns(T::Boolean) }
      def disable!
        @enabled = false
      end

      sig do
        params(
          name: String,
          reason: String,
          decision: T.nilable(Symbol),
          disclose_subject_existence: T::Boolean,
          halt: T::Boolean
        ).returns(T.self_type)
      end
      def stepped(
        name:,
        reason:,
        decision: nil,
        disclose_subject_existence: false,
        halt: false
      )
        decision(decision) if decision
        return self unless enabled

        steps << {
          name: name,
          reason: reason,
          decision: decision,
          disclose_subject_existence: disclose_subject_existence,
          halt: halt
        }

        self
      end

      sig { params(decision: Symbol).returns(Symbol) }
      def decision(decision)
        @status = decision == :success ? decision : :failed
      end

      sig { params(other: ExecutionLog).returns(ExecutionLog) }
      def merge(other)
        return self unless enabled && other.enabled
        @steps += other.steps
        decision(other.status)
        self
      end
    end
  end
end
