# typed: true
# frozen_string_literal: true

module Copilot::Mcp::ControllerMethods
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { ApplicationController }

  included do
    T.bind(self, T.class_of(ApplicationController))
  end

  def target_for_conditional_access
    # The MCP controllers require the user to be logged in, but this filter
    # gets called before `login_required`, so we have to handle the case
    # where `current_user` is `nil`.
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end

  def resource_for_conditional_access
    return self unless logged_in?

    current_user
  end
end
