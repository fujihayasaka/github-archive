# typed: true
# frozen_string_literal: true

module Platform
  module Scalars
    class GitRefname < Platform::Scalars::Base
      description "A fully qualified reference name (e.g. `refs/heads/master`)."

      def self.coerce_input(value, context)
        return nil unless value.start_with?("refs/")
        return nil if RefUpdatesPolicy::HIDDEN_REFS.include?(value)
        return nil if value.start_with?(*RefUpdatesPolicy::HIDDEN_REF_PREFIXES)
        return nil unless Rugged::Reference.valid_name?(value)

        value
      end

      def self.coerce_result(value, context)
        value
      end
    end
  end
end
