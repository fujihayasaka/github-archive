# typed: true
# frozen_string_literal: true

module Forks::ForksControllerDependency
  include GitHub::Memoizer

  extend T::Helpers

  requires_ancestor { ApplicationController }

  memoize def user_settings_record
    current_user&.user_settings_record
  end

  def unbound_period_enabled?
    # If removing this feature flag, make sure to remove
    # references to `:unbound_period` within the forks package also!
    user_or_global_feature_enabled?(:forks_view_unbound_period)
  end

  memoize def user_default_options
    return {} unless user_settings_record
    JSON.parse(user_settings_record.get(:forks_view_default_options)).symbolize_keys
  end

  sig { returns(ActionController::Parameters) }
  def permitted_params
    params.permit(:sort_by, :period, :page, :user_id, :repository, :include)
  end

  sig { returns(Forks::SearchOptionsResolver) }
  memoize def safe_options_resolver
    # Start with the default options and enable any flags for the actor
    options = Forks::SearchOptionsResolver.new
    options.enable_feature(:unbound_period) if unbound_period_enabled?
    user_default_state = options
    # If this is enabled, fetch the user's options and override the defaults
    options = options.copy(**user_default_options)
    user_default_state = options
    # Lastly, override the fully resolved defaults with any included params
    options = options.copy(**permitted_params.to_h.symbolize_keys)

    # persisted=true indicates to the front end that the user should not be able to click the
    # save button, since the current state is already the user's default.
    options.persisted = true if user_default_state.to_options_args == options.to_options_args

    options.freeze
  end
end
