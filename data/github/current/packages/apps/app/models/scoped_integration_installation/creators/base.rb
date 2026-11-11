# typed: true
# frozen_string_literal: true

# A work in progress. A place to extract common functionality from the three
# scoped installation creators. If it can be a pure function, it probably
# doesn't belong here. If it depends on some instance variable that can vary
# between creators, it probably does.
class ScopedIntegrationInstallation
  module Creators
    class Base
      include GitHub::Memoizer

      EXPIRATION_WINDOW = 25.hours
      MAXIMUM_EXPIRATION_EXTENSION_THRESHOLD = 5.hours

      attr_reader :entry_point

      # Internal: Date/Time stamp representing when this installation (and its
      # permissions) should expire.
      memoize def expiry
        EXPIRATION_WINDOW.from_now
      end

      # Internal: Should this installation expire?
      def expires?
        @expires
      end

      # Internal: Returns an expiry Date/Time stamp or nil if this installation
      # does not expire.
      #
      # Sub-classes should use this method in preference to .expiry to take
      # advantage of the `nil` behavior, which is necessary for correctly
      # creating database records without a timestamp: E.g. nil.to_i !== nil.
      def expires_at
        expires? ? expiry : nil
      end

      def extend_expires_at(installation)
        track_remaining_expiry(installation)
        if (installation.expires_at - Time.now.utc) < MAXIMUM_EXPIRATION_EXTENSION_THRESHOLD
          installation.extend_expires_at(EXPIRATION_WINDOW.from_now, async: true, entry_point: entry_point)
        end
      end

      def track_remaining_expiry(installation)
        remaining_expiry_in_hours = ((installation.expires_at - Time.now) / 1.hour).round
        GitHub.dogstats.distribution(
          "#{remaining_expiry_tag_prefix}.perform_with_cache.remaining_expiry_in_hours",
          remaining_expiry_in_hours,
        )
      end

      def remaining_expiry_tag_prefix
        raise NotImplementedError.new("remaining_expiry_tag_prefix must be implemented in a sub-class")
      end

      def valid_permissions?
        validate_permissions!; true
      rescue ScopedIntegrationInstallation::Result::Error
        false
      end

      def validate_permissions!
        raise NotImplementedError.new("validate_permissions! must be implmented in a sub-class")
      end
    end
  end
end
