# typed: false
# frozen_string_literal: true

module GitHub
  module Config
    module SupportLink
      DOTCOM_DEFAULT_SUPPORT_EMAIL = "support@github.com".freeze

      # Get the support link which is configured at stafftools by a siteadmin, to be used in the app. Loaded via the
      # ENTERPRISE_SUPPORT_LINK environment variable in GHES.
      #
      # @support_link is always accompained with @support_link_type
      # For enterprise instances that have not upgraded to a version
      # with this feature, there will only be @support_email set
      #
      # Returns String.
      def support_link
        @support_link || @support_email || (enterprise? ? default_support_email : GitHub.support_url)
      end
      attr_writer :support_link
      attr_writer :support_email # Supporting @support_email for legacy purposes

      # Get the support link type for the matching #support_link.
      # Support link type can be "email" or "url" depending on configuration.
      # Loaded via the ENTERPRISE_SUPPORT_LINK_TYPE environment variable in GHES.
      # If not set (on dotcom) then returns "url".
      #
      # Returns String.
      def support_link_type
        @support_link_type || (enterprise? ? "email" : "url")
      end
      attr_writer :support_link_type

      # The noreply address is the "unconfigured" default on Enterprise if the
      # admins have not set a support email address. We should not link to or
      # show this default value on Enterprise if it can avoided, but will need
      # to use it in some cases such as outgoing emails if nothing more
      # appropriate is available. For example if nothing is set, or if a
      # support link is being used instead of a support email.
      def default_support_email
        enterprise? ? GitHub.urls.noreply_address : DOTCOM_DEFAULT_SUPPORT_EMAIL
      end

      def support_link_text
        support_link_type == "url" ? "Please visit #{support_link}" : "Please contact #{who_to_contact}"
      end

      # Makes just the first word in support_link_text lowercase
      def support_link_text_lowercase
        support_link_type == "url" ? "please visit #{support_link}" : "please contact #{who_to_contact}"
      end

      def support_link_text_no_link
        support_link_type == "url" ? "Please visit" : "Please contact"
      end

      def support_link_text_no_link_lowercase
        support_link_text_no_link.downcase
      end

      def support_link_text_no_please
        support_link_type == "url" ? "visit #{support_link}" : "contact #{who_to_contact}"
      end

      def support_link_text_no_please_no_link
        support_link_type == "url" ? "visit" : "contact"
      end

      def support_link_text_mailto_or_link
        support_link_type == "url" ? "#{support_link}" : "mailto:#{support_link}"
      end

      # Prefer using support_link and text methods
      # However code such as ApplicationMailer needs an email address,
      # so this code uses support_link if its an email otherwise it uses defaults
      def support_email
        if support_link_type == "email"
          support_link
        else
          default_support_email
        end
      end

      # Is the current support email configured correctly
      # (as by default it is not on Enterprise)?
      def support_link_not_enterprise_default?
        return true unless enterprise?
        support_link != GitHub.urls.noreply_address
      end

      def enterprise_support_link
        GitHub.support_url
      end

      private

      def who_to_contact
        if support_link_not_enterprise_default?
          support_link
        else
          "your local #{flavor} site administrator"
        end
      end

    end
  end

  extend Config::SupportLink
end
