# typed: true
# frozen_string_literal: true

module GitHub
  module Enterprise
    class Certificate
      CERT_EXPIRATION_WARNING_THRESHOLD = 30.days

      # DateTime at which the certificate expires.
      attr_reader :expires_at

      # x509 - an OpenSSL::X509::Certificate for the GitHub Enterprise install
      #
      def initialize(x509)
        @expires_at = x509.not_after
      end

      # The number of days until the certificate expires.
      #
      # Returns an Integer of days.
      def days_until_expiration
        [0, ((expires_at.to_i - Time.now.to_i) / 1.0.day).round].max
      end

      # Will this certificate expire within 30 days?
      #
      # Returns true when expiring within 30 days, otherwise false.
      def close_to_expiration?
        # CERT_EXPIRATION_WARNING_THRESHOLD.parts
        # => [[:days, 30]]
        days_until_expiration <= CERT_EXPIRATION_WARNING_THRESHOLD.parts.first[1]
      end

      # Should we show the expiration warning to the given user?
      #
      # user - the staff User record.
      #
      # Returns true if applicable, otherwise false.
      def show_warning?(user)
        user.site_admin? && close_to_expiration? && !warning_hidden?(user)
      end

      # Hide the expiration warning for the given user.
      #
      # user - the User record.
      #
      # Returns nothing.
      def hide_warning(user, expires: nil)
        # rubocop:todo GitHub/DoNotUseGlobalKv
        GitHub.kv.set("enterprise:hide-warning:certificate-expiring:#{user.id}", "1", expires: expires)
        # rubocop:enable GitHub/DoNotUseGlobalKv
      end

      # Is the expiration warning hidden for the given user?
      #
      # user - the User record.
      #
      # Returns true if hidden, false otherwise.
      def warning_hidden?(user)
        # rubocop:todo GitHub/DoNotUseGlobalKv
        GitHub.kv.get("enterprise:hide-warning:certificate-expiring:#{user.id}").value!
        # rubocop:enable GitHub/DoNotUseGlobalKv
      end
    end
  end
end
