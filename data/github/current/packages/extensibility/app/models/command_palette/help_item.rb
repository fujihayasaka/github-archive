# typed: true
# frozen_string_literal: true

module CommandPalette
  # A value class used to configure a help item.
  class HelpItem
    class UnknownScope < ArgumentError; end

    SCOPES = [:global, :owner, :repository].freeze

    attr_reader :title, :group, :prefix, :scope_types
    def initialize(title:, group:, prefix: nil, scope_types: [])
      @title = title
      @group = group
      @prefix = prefix

      if Rails.env.test? || Rails.env.development?
        scope_types.each do |scope_type|
          raise UnknownScope, "Unknown scope type: #{scope_type}" unless SCOPES.include?(scope_type)
        end
      end

      # Scopes which this help item is enabled for.
      # If empty, the help item is enabled for any scope
      @scope_types = scope_types
        .map { |scope_type| scope_type == :global ? "" : scope_type }
        .map(&:to_s)
        .uniq
    end

    def hint
      prefix
    end
  end
end
