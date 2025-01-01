# typed: true
# frozen_string_literal: true

class SiteScopedIntegrationInstallation
  module Editors
    class Result
      class Error < StandardError; end

      def self.success(installation) new(:success, installation: installation) end
      def self.error(error) new(:error, error: error) end
      def self.failed(reason) new(:failed, reason: reason) end

      attr_reader :error, :installation, :reason, :status

      def initialize(status, installation: nil, error: nil, reason: nil)
        @status       = status
        @installation = installation
        @error        = error
        @reason       = reason
      end

      def success?
        @status == :success
      end

      def failed?
        !success?
      end
    end
  end
end
