# typed: true
# frozen_string_literal: true

module ProgrammaticAccess
  class DeepLinkExpirationValidator

    DEFAULT_FALLBACK_EXPIRATION_DAYS = 30
    FINE_GRAINED_PAT_WITH_NO_POLICY_EXPIRATION_LIMIT = 365

    class Result
      attr_reader :status, :default_expires_at, :custom_expires_at, :message

      def self.success(default_expires_at:, custom_expires_at: nil)
        new(:success, default_expires_at: default_expires_at, custom_expires_at: custom_expires_at)
      end

      def self.warning(message)
        new(:warning, message: message)
      end

      def initialize(status, default_expires_at: nil, custom_expires_at: nil, message: nil)
        @status = status
        @default_expires_at = default_expires_at
        @custom_expires_at = custom_expires_at
        @message = message
      end

      def success?
        status == :success
      end
    end

    def self.validate(expires_in:, target:, user:)
      new(expires_in, target, user).validate
    end

    def initialize(expires_in, target, user)
      @expires_in_param = expires_in
      @target = target
      @user = user
    end

    def validate
      none_result = validate_none_expiration
      return none_result if none_result

      begin
        expires_in = Integer(@expires_in_param)
        rescue ArgumentError, TypeError
          return invalid_integer_warning
      end

      return Result.warning("`expires_in` must be a positive integer.") if expires_in <= 0

      if expires_in > applicable_expiration_limit
        Result.warning(
          "The requested expiration (#{expires_in} #{'day'.pluralize(expires_in)}) exceeds the allowed limit of #{applicable_expiration_limit} #{'day'.pluralize(applicable_expiration_limit)} for #{@target.display_login}."
        )
      else
        Result.success(default_expires_at: "custom", custom_expires_at: expires_in.days.from_now.to_date)
      end
    end

    private

    def validate_none_expiration
      return unless @expires_in_param == "none"

      if no_expiration_allowed?
        Result.success(default_expires_at: "none")
      else
        Result.warning("The selected resource owner requires tokens to expire within #{applicable_expiration_limit} #{'day'.pluralize(applicable_expiration_limit)}. 'No expiration' is not allowed.")
      end
    end

    def invalid_integer_warning
      message = "Invalid expiration value. The `expires_in` query must be an integer"
      message += " or choose 'No expiration'" if no_expiration_allowed?
      message += "."
      Result.warning(message)
    end

    def no_expiration_allowed?
      policy_limit.nil? || user_is_exempt?
    end

    def applicable_expiration_limit
      (!policy_limit.nil? && !user_is_exempt?) ? policy_limit : FINE_GRAINED_PAT_WITH_NO_POLICY_EXPIRATION_LIMIT
    end

    def policy_limit
      @policy_limit ||= ApplicationController.helpers.fine_grained_lifetime_limit_for(@target)
    end

    def user_is_exempt?
      return @user_is_exempt if defined?(@user_is_exempt)
      @user_is_exempt = policy_limit && ApplicationController.helpers.fine_grained_lifetime_limit_exempted_for?(@target, @user)
    end
  end
end
