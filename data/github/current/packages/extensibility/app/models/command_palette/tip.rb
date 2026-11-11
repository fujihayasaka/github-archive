# typed: true
# frozen_string_literal: true

module CommandPalette
  # A value class used to configure a tip.
  class Tip
    class UnknownScope < ArgumentError; end

    SCOPES = [:global, :owner, :repository].freeze

    attr_reader :title, :prefix, :mode, :scope_types

    def initialize(title:, prefix: nil, mode: nil, scope_types:)
      @title = title
      @prefix = prefix
      @mode = mode

      if Rails.env.test? || Rails.env.development?
        scope_types.each do |scope_type|
          raise UnknownScope, "Unknown scope type: #{scope_type}" unless SCOPES.include?(scope_type)
        end
      end

      # Scopes which this tip is enabled for.
      @scope_types = scope_types
        .map { |scope_type| scope_type == :global ? "" : scope_type }
        .map(&:to_s)
        .uniq
    end
  end
end
