# typed: true
# frozen_string_literal: true

module GitHub
  module Messaging
    class Error < StandardError
      attr_reader :code

      def set_code(code)
        @code = code
      end
    end

    class NumberNotMobileError < Error
      def initialize(*args)
        super "the number doesn't seem to be a mobile number"
      end
    end

    class NumberNotValidError < Error
      def initialize(*args)
        super "the number doesn't seem to be valid"
      end
    end

    class AreaNotSupportedError < Error
      def initialize(*args)
        super "our SMS provider doesn't deliver to your area"
      end
    end

    class TimeoutError < Error
      def initialize(*args)
        super "we are having trouble communicating with our SMS provider"
      end
    end

    class ServerError < Error
      def initialize(*args)
        super "there was an unexpected error sending the SMS"
      end
    end

    class AuthenticationError < Error
      def initialize(*args)
        super "there was an unexpected error sending the SMS"
      end
    end

    class ClientError < Error
      def initialize(*args)
        super "there was an unexpected error sending the SMS"
      end
    end

    class UnknownError < Error
      def initialize(*args)
        super "there was an unexpected error sending the SMS"
      end
    end

    class BillingError < Error
      def initialize(*args)
        super "there was an unexpected error sending the SMS"
      end
    end

    class RateLimitError < Error
      def initialize(*args)
        super "too many SMS messages have been sent to this number recently"
      end
    end

    class UnauthorizedRecipientError < Error
      def initialize(*args)
        super "we are not authorized to send SMS messages to this recipient"
      end
    end

    class RegionNotGeoPermissionedError < Error
      def initialize(*args)
        super "geo-permissions not enabled for this recipient's region"
      end
    end
  end
end
