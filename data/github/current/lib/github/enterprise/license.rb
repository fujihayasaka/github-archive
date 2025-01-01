# typed: true
# frozen_string_literal: true

module GitHub
  module Enterprise
    class License
      require "tempfile"

      # The enterprise-crypto library seems to not be thread-safe, so prevent weird deadlocks we synchronize our usage of it.
      @@enterprise_crypto_lock = Monitor.new

      if GitHub.enterprise?
        require "enterprise/crypto"
        include ::Enterprise
      end

      attr_reader :company

      # DateTime at which the license expires.
      attr_reader :expire_at

      # The maximum number of seats allowed by this license.
      #
      # Returns the Integer number of seats or nil for evaluations.
      attr_reader :seats

      # Some customers may have a perpetual license which does not expire.
      attr_reader :perpetual

      # Whether the license is an evaluation license or not.
      attr_reader :evaluation

      # Some customers may have an unlimited license with no maximum seat count.
      attr_reader :unlimited

      # Allows configuration of all github_connect features and skips connection addendum.
      attr_reader :github_connect_support

      # Whether the customer has agreed to a custom terms of service.
      attr_reader :custom_terms

      # Whether the customer has purchased Advanced Security.
      attr_reader :advanced_security_enabled

      # Whether the license is enabled for metered billing.
      attr_reader :metered

      def initialize(sync_global_business: true)
        @@enterprise_crypto_lock.synchronize do
          @vault = ::Enterprise::Crypto::LicenseVault.new(license_key_data)
          ::Enterprise::Crypto.customer_vault = ::Enterprise::Crypto::CustomerVault.new(customer_key_data)

          reload!(sync_global_business: sync_global_business)
        end
      end

      def reload!(sync_global_business: true)
        license = @@enterprise_crypto_lock.synchronize do
          ::Enterprise::Crypto::License.load(license_data, @vault)
        end

        @company                   = license.company
        @expire_at                 = license.expire_at
        @seats                     = license.seats
        @perpetual                 = license.perpetual
        @evaluation                = license.evaluation
        @unlimited                 = license.unlimited_seating
        @github_connect_support    = license.croquet_support
        @custom_terms              = license.custom_terms
        @advanced_security_enabled = license.advanced_security_enabled
        @advanced_security_seats   = license.advanced_security_seats
        @metered                   = license.metered

        sync_with_global_business if sync_global_business
      rescue ::Enterprise::Crypto::Error => e
        @expire_at = @seats = nil
        ## TODO: log this error
      end

      # The maximum number of seats allowed by this license in a readable format.
      # Primarily used to present values other than 0 to customers via the license
      # settings API for total seats allowed.
      #
      # Returns descriptive string for unlimited and evaluation licenses and
      # a Integer for the number of seats.
      def readable_seats
        if has_seat_limit?
          seats
        else
          "unlimited"
        end
      end

      # The kind of license being used.
      #
      # Returns a string describing the type of license.
      def kind
        if evaluation?
          "evaluation"
        elsif unlimited?
          "unlimited"
        elsif perpetual?
          "perpetual"
        else
          "standard"
        end
      end

      # A license should have enough data to be considered perputal or
      # expiring. If not, it has probably been tampered with and is
      # therefor invalid.
      def valid?
        perpetual? || expires?
      end

      # Whether the enterprise license is for an evaluation or not.
      #
      # Returns true if this is a trial enterprise license.
      def evaluation?
        !!@evaluation
      end

      # Whether the enterprise license is for an unlimited seat license or not.
      #
      # Returns true if this is an unlimited license.
      def unlimited?
        !!@unlimited
      end

      # Does the license ever expire?
      #
      # Returns true if an expiration date is set, false otherwise.
      def expires?
        !perpetual? && expire_at.is_a?(Date)
      end

      # Determine if the license has expired.
      #
      # Returns true if a license expiration date is set and it's in the past.
      def expired?
        expires? && expire_at < DateTime.now
      end

      # Determine if the license is perpetual.
      #
      # Returns true if a license is perpetual.
      def perpetual?
        !!@perpetual
      end

      # Whether seat restrictions are enabled.
      #
      # Returns true if the seat limit is non-zero, false otherwise.
      def has_seat_limit?
        !evaluation? && !unlimited?
      end

      # The number of days until the Enterprise license expires.
      #
      # Returns an Integer of days.
      def days_until_expiration
        return if !expires?

        [0, ((expire_at.to_i - Time.now.to_i) / 1.0.day).round].max
      end

      # Is this license close to running out of seats or about to expire?
      #
      # Returns true when close to limits, false otherwise.
      def close_to_limit?(type)
        case type
        when :seat_limit
          close_to_seat_limit?
        when :expiration
          close_to_expiration?
        end
      end

      # Will this license expire in two weeks?
      #
      # Returns true when time is running out, false otherwise.
      def close_to_expiration?
        return false if !expires?
        expire_at < 15.days.from_now
      end

      # The number of seats purchased for Advanced Security.
      def advanced_security_seats
        @advanced_security_seats || 0
      end

      # Is GHAS billed as metered for this business?
      def metered_advanced_security?
        metered? && advanced_security_seats.zero?
      end

      # Does the license have metered billing enabled for this business?
      def metered?
        !!@metered
      end

      # Whether the enterprise license has github_connect_support?
      #
      # Returns true if this supports github_connect
      def github_connect_support?
        !!@github_connect_support
      end

      # Whether the customer has agreed to custom_terms?
      #
      # Returns true if custom terms
      def custom_terms?
        !!@custom_terms
      end

      # Read the information inside a .ghl.
      #
      # Returns the content of the .ghl as a String.
      def license_data
        File.read(GitHub.license_path, mode: "rb")
      end

      # Read the information about the license key.
      #
      # Returns the content of the key as a String.
      def license_key_data
        File.read(GitHub.license_key, mode: "rb")
      end

      # Read the information about the customer key.
      #
      # Returns the content of the key as a String.
      def customer_key_data
        File.read(GitHub.customer_key, mode: "rb")
      end

      #####################################################
      ## TODO: weird stuff that doesn't belong in this class
      #####################################################

      # The expiration formatted for humans such as "December 12, 2011".
      #
      # Returns the date as a String.
      def formatted_expiration_date
        @expire_at.strftime("%B %d, %Y")
      end

      # Does this license only have five seats left? Evaluation license do not
      # enforce a seat limit.
      #
      # For licenses without a seat limit, the return value is cached for an hour.
      #
      # Returns true when almost out of seats, false otherwise.
      def close_to_seat_limit?
        return false unless has_seat_limit?

        # Cache this value for an hour, and avoid the costly #seats_used call
        # made via #seats_available.
        GitHub.cache.fetch("enterprise:close-to-seat-limit", ttl: 1.hour) do
          seats_available <= 5
        end
      end

      # Has the installation reached or exceeded the number of seats available
      # with this license?
      #
      # Returns true if at or above the limit or in evalution mode, false
      # otherwise.
      def reached_seat_limit?
        return false unless has_seat_limit?
        seats_used >= seats
      end

      # Returns the Integer number of seats in use.
      #
      # See also User.count_seats_used
      def seats_used
        User.count_seats_used
      end

      # Returns the Integer number of licensed seats available.
      def seats_available
        [0, seats - seats_used].max
      end

      def readable_seats_available
        has_seat_limit? ? seats_available : "unlimited"
      end

      # Should we show the license expiration warning to the given user?
      #
      # user - the staff User record.
      #
      # Returns true if applicable, false otherwise.
      def show_warning?(user, type)
        user.site_admin? && !warning_hidden?(user, type) && close_to_limit?(type)
      end

      # Hide the license expiration warning for the given user.
      #
      # user - the User record.
      #
      # Returns nothing.
      def hide_warning(user, type, expires: nil)
        # rubocop:todo GitHub/DoNotUseGlobalKv
        GitHub.kv.set("enterprise:hide-warning:#{type}:#{user.id}", "1", expires: expires)
        # rubocop:enable GitHub/DoNotUseGlobalKv
      end

      # Reveal the license expiration warning for the given user.
      #
      # user - the User record.
      #
      # Returns nothing.
      def reveal_warning(user, type)
        GitHub.kv.del("enterprise:hide-warning:#{type}:#{user.id}") # rubocop:todo GitHub/DoNotUseGlobalKv
      end

      # Is the license warning hidden for the given user?
      #
      # user - the User record.
      #
      # Returns true if hidden, false otherwise.
      def warning_hidden?(user, type)
        GitHub.kv.get("enterprise:hide-warning:#{type}:#{user.id}").value! # rubocop:todo GitHub/DoNotUseGlobalKv
      end

      # Sync the license data with the global business.
      #
      # Returns the global Business if successful, otherwise false.
      def sync_with_global_business
        return unless GitHub.single_business_environment? && GitHub.global_business

        GitHub.global_business.sync_enterprise_license self
      end
    end
  end
end
