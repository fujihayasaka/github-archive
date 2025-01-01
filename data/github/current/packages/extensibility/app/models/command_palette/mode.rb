# typed: true
# frozen_string_literal: true

module CommandPalette
  # A value class used to configure a provider's mode
  class Mode
    class UnknownScope < ArgumentError; end
    # Mode that is active all the time (matches any mode).

    SCOPES = [:global, :owner, :repository].freeze

    attr_reader :character, :placeholder, :scope_types
    def initialize(character:, placeholder:, scope_types: [])
      @character = character
      @placeholder = placeholder

      if Rails.env.test? || Rails.env.development?
        scope_types.each do |scope_type|
          raise UnknownScope, "Unknown scope type: #{scope_type}" unless SCOPES.include?(scope_type)
        end
      end

      # Scopes which this mode is enabled for.
      # If not given then mode is enabled for any scope
      @scope_types = scope_types
        .map { |scope_type| scope_type == :global ? "" : scope_type }
        .map(&:to_s)
        .uniq
    end
  end
end
