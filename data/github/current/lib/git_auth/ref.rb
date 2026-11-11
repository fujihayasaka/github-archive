# typed: true
# frozen_string_literal: true

module GitAuth
  class Ref
    attr_reader :encoded_name, :before, :after, :status, :decision
    attr_accessor :message, :display_message
    def initialize(encoded_name, before, after, status = nil)
      @encoded_name, @before, @after, @status = encoded_name, before, after, status
      @decision = :undecided
    end

    def decoded_name
      @decoded_name ||= Addressable::URI.unescape(encoded_name)
    end

    # When called, this rule will be allowed, but all rules not yet run will be ignored.
    def allow_and_ignore_all_other_rules!
      @decision = :allow
    end

    def allow?
      decision == :allow
    end

    def disallow!(message)
      @decision = :disallow
      @message = message
    end

    def undecided?
      decision == :undecided
    end

    def disallowed?
      decision == :disallow
    end

    def payload
      if status
        [decoded_name, before, after, status]
      else
        [decoded_name, before, after]
      end
    end

    def ok!
      self.message ||= "ok #{before} #{after}"
    end

    def failed!
      self.message ||= "failed"
    end
  end
end
