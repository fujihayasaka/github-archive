# typed: true
# frozen_string_literal: true

module Platform
  class SchemaRuntimeMask < SchemaVersionMask
    extend T::Sig

    sig { params(target: Symbol, environment: T.any(T.nilable(String), Symbol)).void }
    def initialize(target, environment: GitHub.runtime.current)
      super
      @now = Time.now.utc
    end

    def hidden?(member, context)
      super ||
      hidden_by_feature_flag?(member, context) ||
      hidden_by_mobile_app?(member, context) ||
      hidden_by_deprecation?(member, context)
    end

    private

    attr_reader :now

    def hidden_by_feature_flag?(member, context)
      if @target == :internal
        # internal schema, return all the things
        false
      elsif member.respond_to?(:feature_flag) && (required_flag = member.feature_flag)
        # Make sure the provided flags include the required one
        # (`context[:feature_flags]` is filtered for the current viewer in `Platform.execute`)
        !context[:feature_flags].include?(required_flag)
      else
        # There's no flag on this member
        false
      end
    end

    def hidden_by_mobile_app?(member, context)
      if @target == :internal
        # internal schema, return all the things
        false
      elsif member.respond_to?(:mobile_only) && member.mobile_only
        # Hide the member if it is only available to mobile, and the current oauth app
        # is NOT the mobile app OR the it doesn't have another specified capability
        has_schema_runtime_mask_capability = Apps::Internal.capable?(:mobile_only_schema_mask, app: context[:oauth_app])
        return false if has_schema_runtime_mask_capability

        if member.respond_to?(:required_capabilities) && member.required_capabilities.kind_of?(Array)
          member.required_capabilities.each do |required_capability|
            return false if Apps::Internal.capable?(
              required_capability,
              app: context[:oauth_app] || context[:integration],
            )
          end
        else
          true
        end
      else
        false
      end
    end

    NO_PREVIEWS = [].freeze


    def hidden_by_deprecation?(member, context)
      # Don't hide deprecated fields for enterprise,
      # Use versions instead to sunset fields.
      return false if GitHub.enterprise?
      return false if @target == :internal
      return false unless member.respond_to?(:upcoming_change)
      return false unless change = member.upcoming_change
      now >= change.apply_on && change.active?
    end
  end
end
