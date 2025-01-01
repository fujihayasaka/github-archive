# typed: true
# frozen_string_literal: true

module Platform
  class SchemaRuntimeMask < SchemaVersionMask
    sig { params(target: Symbol, environment: T.any(T.nilable(String), Symbol)).void }
    def initialize(target, environment: GitHub.runtime.current)
      super
      @now = Time.now.utc
    end

    def hidden?(member, context)
      super ||
      hidden_by_feature_flag?(member, context) ||
      hidden_by_deprecation?(member, context) ||
      hidden_by_required_capabilities?(member, context)
    end

    private

    attr_reader :now

    def hidden_by_feature_flag?(member, context)
      # Internal schema target should not hide any GraphQL members
      return false if @target == :internal

      # No flag on this member, so it's not hidden
      return false unless member.respond_to?(:feature_flag) && member.feature_flag

      # Make sure the provided flags include the required one
      # (`context[:feature_flags]` is filtered for the current viewer in `Platform.execute`)
      context[:feature_flags].exclude?(member.feature_flag)
    end

    def hidden_by_required_capabilities?(member, context)
      # Internal schema target should not hide any GraphQL members
      return false if @target == :internal

      # Show if the member does not support or have required capabilities
      return false unless member.respond_to?(:required_capabilities) &&
        member.required_capabilities.kind_of?(Array) &&
        member.required_capabilities.any?

      # If the member has required capabilities, check if the current oauth app has at least one of them.
      # If none are found, this check returns true to hide the member with the schema runtime mask.
      member.required_capabilities.none? do |required_capability|
        Apps::Privileged.capable?(required_capability, app: context[:oauth_app] || context[:integration])
      end
    end

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
