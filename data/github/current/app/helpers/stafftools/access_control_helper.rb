# typed: true
# frozen_string_literal: true

module Stafftools::AccessControlHelper
  include Kernel

  # View helper to check if the current user is authorized to access a given
  # controller/action combo in `config/stafftools_permissions.yml`.
  #
  # Requires two parameters as in the options hash:
  #   controller: (required) the controller the action lives in
  #   action: (required) the controller action to be authorized
  #
  # Returns Boolean.
  def stafftools_action_authorized?(options = {})
    return true if GitHub.enterprise?

    begin
      controller = options.fetch(:controller).to_s
      action = options.fetch(:action).to_s
    rescue KeyError
      raise ArgumentError, "The :controller and :action options are required for the #stafftools_action_authorized? check"
    end

    # Must be an existing controller and action
    msg = "#{controller} and #{action} are not a valid controller and action combination"
    begin
      cc = controller.constantize
      raise ArgumentError, msg unless cc < ApplicationController && cc.action_methods.include?(action)
    rescue NameError
      raise ArgumentError, msg
    end

    stafftools_action = {
      controller: controller,
      action: action,
    }

    Stafftools::AccessControl.authorized?(T.unsafe(self).current_user, stafftools_action)
  end
end
