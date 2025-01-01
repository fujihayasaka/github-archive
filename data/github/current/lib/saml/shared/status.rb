# typed: true
# frozen_string_literal: true

module SAML
  module Shared
    # This module defines shared behavior for response message objects that
    # have a Status element.
    #
    # http://www.schemacentral.com/sc/saml2/e-samlp_Status.html
    module Status
      extend ActiveSupport::Concern

      STATUS_CODES = {
        "urn:oasis:names:tc:SAML:2.0:status:Success"        => :success,
        "urn:oasis:names:tc:SAML:2.0:status:AuthnFailed"    => :authn_failed,
        "urn:oasis:names:tc:SAML:2.0:status:RequestDenied"  => :request_denied,
      }

      attr_accessor :status_message  # string friendly message

      # Public: Returns symbol representation of `secondary_status_code` looked up from
      # STATUS_CODES.
      def second_level_status
        @second_level_status || STATUS_CODES.fetch(@second_level_status_code, :unknown)
      end

      def second_level_status=(sls)
        @second_level_status = sls
        @second_level_status_code = STATUS_CODES.key(sls)
      end

      def second_level_status_code=(sc)
        @second_level_status_code = sc
        @second_level_status = STATUS_CODES.fetch(sc, :unknown)
      end

      def second_level_status_code
        @second_level_status_code || STATUS_CODES.key(@second_level_status)
      end

      # Public: Returns symbol representation of `status_code` looked up from
      # STATUS_CODES.
      def status
        @status || STATUS_CODES.fetch(@status_code, :unknown)
      end

      # Public: Complement to #status. This will also set `status_code` based
      # on STATUS_CODES lookup. Returns nothing.
      def status=(s)
        @status = s
        @status_code = STATUS_CODES.key(s)
      end

      def status_code
        @status_code || STATUS_CODES.key(@status)
      end

      # string saml spec value
      def status_code=(sc)
        @status_code = sc
        @status = STATUS_CODES.fetch(sc, :unknown)
      end

      # Public: boolean whether `status` is :success
      def success?
        status == :success
      end

      # Public: boolean whether `status` is :request_denied
      def request_denied?
        second_level_status == :request_denied
      end

      private

      # Private: Generate XML for `Status` element. `builder` is an instance
      # of Nokogiri::XML::Builder.
      def generate_status(builder)
        return unless status_code

        builder["samlp"].Status("xmlns:samlp" => "urn:oasis:names:tc:SAML:2.0:protocol") do |builder|
          builder["samlp"].StatusCode("Value" => status_code) do |builder|
            builder["samlp"].StatusCode("Value" => second_level_status_code) if second_level_status_code
          end
          builder["samlp"].StatusMessage(status_message) if status_message.present?
        end
      end
    end
  end
end
