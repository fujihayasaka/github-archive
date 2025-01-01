# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Adds `table` role to `<table>` elements generated with markdown.
  class SetTableRoleFilter < NodeFilter
    SELECTOR = Goomba::Selector.new("table")

    def initialize(*args)
      super
      @filter = GitHub::HTML::SetTableRoleFilter.new("", context, result)
    end

    def self.enabled?(context)
      context.fetch(:set_table_role, true)
    end

    def selector
      SELECTOR
    end

    def call(element)
      @filter.call_element(element)
    end
  end
end
