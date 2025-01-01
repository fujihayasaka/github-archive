# typed: true
# frozen_string_literal: true

class Stafftools::Codespaces::CodespaceUserSettingsComponent < ApplicationComponent
  attr_reader :user

  def initialize(user)
    @user = user
  end

  def codespace_retention_period_for_user
    user.codespace_default_retention_period.present? ? user.codespace_default_retention_period.minutes.in_days.to_i : Codespace::MAX_RETENTION_PERIOD.minutes.in_days.to_i
  end

  def codespace_idle_timeout_for_user
    user.codespace_default_idle_timeout || Codespaces::VscsClient::AUTO_SHUTDOWN_MINUTES
  end

  def gpg_authorization_setting
    user.gpg_authorization
  end

  def render?
    user.user?
  end
end
