# typed: strict
# frozen_string_literal: true

module ZeroUserConcern
  extend ActiveSupport::Concern
  extend T::Helpers
  requires_ancestor { DashboardController }

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def dashboard_refresh_props
    {
      new_user_getting_started_checklist:,
      dismissals:
    }
  end

  private

  sig { returns(T::Hash[Symbol, T::Boolean]) }
  def new_user_getting_started_checklist
    # TODO: skip this check when the checklist module has been dismissed

    {
      has_customized_account: user_setting_for(:new_user_has_customized_account),
      has_tried_copilot: user_setting_for(:new_user_has_tried_copilot),
      has_created_repo: user_setting_for(:new_user_has_created_repo)
    }
  end

  sig { returns(T::Hash[Symbol, T::Boolean]) }
  def dismissals
    {
      playlist_dismissed: user_settings_value_for(:nux_dashboard_playlist_dismissed),
      getting_started_dismissed: user_settings_value_for(:nux_dashboard_getting_started_dismissed),
      docs_dismissed: user_settings_value_for(:nux_dashboard_docs_dismissed),
      recommendations_dismissed: user_settings_value_for(:nux_dashboard_recommendations_dismissed),
      vscode_dismissed: user_settings_value_for(:nux_dashboard_vscode_dismissed),
      desktop_dismissed: user_settings_value_for(:nux_dashboard_desktop_dismissed)
    }
  end

  sig { params(setting_key: Symbol).returns(T.untyped) }
  def user_setting_for(setting_key)
    return false unless current_user&.feature_enabled?(:nux_dashboard_refresh)
    return true if user_settings_value_for(setting_key)

    getting_started_user_methods[setting_key].call(current_user).tap do |value|
      persist_user_setting_for(setting_key) if value
    end
  end

  # This hash maps settings keys to lambda functions that call the corresponding user methods.
  # To avoid Rubocop's AvoidObjectSendWithDynamicMethod warning, we use explicit lambdas instead of metaprogramming.
  # This is also more readable than passing a block to each method call.
  sig { returns(T::Hash[T.untyped, T.untyped]) }
  def getting_started_user_methods
    {
      new_user_has_customized_account: ->(user) { user.has_customized_account? },
      new_user_has_tried_copilot: ->(user) { user.has_tried_copilot? },
      new_user_has_created_repo: ->(user) { user.has_created_repo? }
    }
  end

  sig { params(settings_key: Symbol).returns(T::Boolean) }
  def user_settings_value_for(settings_key)
    ActiveModel::Type::Boolean.new.cast(current_user.settings.get(settings_key))
  end

  sig { params(setting_key: Symbol).void }
  def persist_user_setting_for(setting_key)
    ActiveRecord::Base.connected_to(role: :writing) do
      current_user.settings.set!(setting_key, true.to_s)
    end
  end
end
