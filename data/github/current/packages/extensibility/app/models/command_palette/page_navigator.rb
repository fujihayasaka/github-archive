# typed: true
# frozen_string_literal: true

module CommandPalette
  class PageNavigator
    include ApplicationHelper
    include UrlHelpers
    include UrlHelper

    DEFAULT_PRIORITY = 10

    delegate :current_user, :scope, to: :context
    attr_reader :context

    def self.items(context)
      new(context).items
    end

    def initialize(context)
      @context = context
    end

    def items
      raise NotImplementedError, "Please implement `##{__method__}` on your page navigator"
    end

    private

    # Url helpers sometimes depend on a #params method being present.
    # In this context, it doesn't necessarily make sense to have any concrete parameters.
    def params
      {}
    end

    # Allows the url helpers to work within providers
    def default_url_options
      { host: GitHub.host_name }
    end
  end
end
