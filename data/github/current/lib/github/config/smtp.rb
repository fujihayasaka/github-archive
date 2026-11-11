# typed: false
# frozen_string_literal: true

module GitHub
  module Config
    # Mixin for the GitHub module that contains all SMTP configuration settings
    module Smtp
      # Is SMTP enabled in this environment?
      #
      # Returns true by default.
      # Can return false in Enterprise environments if an admin has disabled SMTP
      # on the appliance.
      #
      # Returns Boolean
      def smtp_enabled?
        return @smtp_enabled if defined?(@smtp_enabled)
        @smtp_enabled = true
      end
      attr_writer :smtp_enabled

      # The SMTP domain name.
      #
      # Returns String
      def smtp_domain
        @smtp_domain ||= host_name
      end
      attr_writer :smtp_domain

      # SMTP server address.
      attr_accessor :smtp_address

      # SMTP port.
      #
      # Returns Integer
      def smtp_port
        @smtp_port ||= 25
      end
      attr_writer :smtp_port

      # Additional SMTP configuration.
      attr_accessor :smtp_user_name
      attr_accessor :smtp_password
      attr_accessor :smtp_authentication

      # Default .com to having it disabled because the
      # front-end & worker machines talk to an MTA on localhost
      #
      # Returns Boolean
      def smtp_enable_starttls_auto
        enterprise? ? @smtp_enable_starttls_auto : false
      end
      attr_writer :smtp_enable_starttls_auto

      # Enterprise customers may want to customize the email address used as the
      # noreply sender.
      #
      # Returns "noreply@<smtp-domain>" by default if not set.
      #
      # Returns String
      def noreply_address
        @noreply_address ||= "noreply@#{smtp_domain}"
      end
      attr_writer :noreply_address
    end
  end

  extend Config::Smtp
end
