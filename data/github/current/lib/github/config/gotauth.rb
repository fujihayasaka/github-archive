# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module Gotauth
      # The address of the gotauth service.
      #
      # e.g. "https://gotauth-production.service.iad.github.net"
      attr_accessor :gotauth_address
      attr_writer :gotauth_redirect
      attr_writer :gotauth_mirror
      attr_writer :gotauth_mirror_percentage

      def gotauth_redirect?
        return false unless GitHub.enterprise?

        @gotauth_redirect || false
      end

      def gotauth_mirror?
        return false unless GitHub.enterprise?
        return false unless @gotauth_mirror

        Kernel.rand < parsed_mirror_percentage / 100.0
      end

      private

      def parsed_mirror_percentage
        percentage = @gotauth_mirror_percentage
        default_percentage = 10.0

        return default_percentage if percentage.nil? || percentage.to_s.empty?

        begin
          numeric_value = Kernel.Float(percentage)
          return default_percentage if numeric_value < 0 || numeric_value > 100
          numeric_value
        rescue TypeError, ArgumentError
          default_percentage
        end
      end
    end
  end

  extend Config::Gotauth
end
