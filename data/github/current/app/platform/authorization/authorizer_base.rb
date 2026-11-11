# typed: true
# frozen_string_literal: true

module Platform
  module Authorization
    class AuthorizerBase
      attr_reader :auth_context, :result

      delegate :request_authn_context, to: :auth_context

      def self.new_from_context(context, result)
        new(context, result)
      end

      def initialize(context, result)
        @auth_context = context
        @result = result
      end

      def authorized?(verb, options)
        false
      end

      def stepped(reason:, decision: nil, disclose_subject_existence: false)
        result.stepped(
          name: self.class.name,
          reason: reason,
          decision: decision,
          disclose_subject_existence: disclose_subject_existence,
          halt: true
        ).success?
      end
    end
  end
end
