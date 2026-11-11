# typed: true
# frozen_string_literal: true

# Renders a dismissible banner to a last owner of an organization or business account, to let them that a minimum of
# two owners is recommended.
class Accounts::LastOwnerBannerComponent < ApplicationComponent
  def initialize(account:, current_user:)
    @account = account
    @current_user = current_user
  end

  private

  def render?
    return false unless GitHub.billing_enabled?
    return false unless @account.present?
    return false unless @current_user.present?
    return false if @current_user.is_first_emu_owner?

    return @account.last_owner?(@current_user) if @account.is_a?(Business)
    return @account.last_admin?(@current_user) if @account.is_a?(Organization)

    false
  end

  def account_display_name
    @account.is_a?(Business) ? "enterprise" : "organization"
  end
end
