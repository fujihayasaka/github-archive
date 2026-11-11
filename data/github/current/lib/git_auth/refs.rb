# typed: true
# frozen_string_literal: true

module GitAuth
  class Refs
    include Enumerable

    def initialize(raw_refs)
      @refs_by_decoded_name = {}
      Array(raw_refs).each do |raw_ref|
        ref = GitAuth::Ref.new(*raw_ref)
        @refs_by_decoded_name[ref.decoded_name] = ref
      end
      @ref_limit_error = false
    end

    attr_writer :ref_limit_error

    def each(&block)
      refs_by_decoded_name.each do |_, ref|
        yield ref
      end
    end

    def [](key)
      refs_by_decoded_name[key]
    end

    def payload
      Hash[self.map { |ref| [ref.encoded_name, ref.message] }]
    end

    def size
      refs_by_decoded_name.size
    end

    def display_message
      message = self.map(&:display_message).compact.join("")
      message = "#{additional_messages.join("\n")}\n#{message}" if additional_messages.any?
      message
    end

    private

    attr_reader :refs_by_decoded_name

    def additional_messages
      messages = []

      if refs_by_decoded_name.keys.count { |ref| ref.start_with?("refs/heads/") } > Pushes::CommitsHelper::LARGE_BRANCH_COUNT_THRESHOLD
        messages << "warning: No webhooks or actions will be performed for this push as it updates more than #{Pushes::CommitsHelper::LARGE_BRANCH_COUNT_THRESHOLD} branches."
      end

      if @ref_limit_error
        messages << "error: Push rulesets are enabled - only #{RuleEngine::Errors::RefLimitReached::THRESHOLD} refs are allowed per push."
      end

      messages
    end
  end
end
