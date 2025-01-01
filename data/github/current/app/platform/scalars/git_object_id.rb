# typed: true
# frozen_string_literal: true

module Platform
  module Scalars
    class GitObjectID < Platform::Scalars::Base
      description "A Git object ID."

      def self.coerce_input(value, context)
        if value =~ /\A[a-f0-9]{40}\z/i
          value.downcase
        else
          # TODO: raise?
          nil
        end
      end

      def self.coerce_result(value, context)
        value
      end
    end
  end
end
