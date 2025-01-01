# typed: true
# frozen_string_literal: true

class Integrations::IndexView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :integrations, :pending_transfers, :owner

  # Public: Can the owner of these integrations create new Apps?
  #
  # Returns a Boolean.
  def can_create_apps?
    return @can_create_apps if defined?(@can_create_apps)

    if owner.user?
      @can_create_apps = true
    elsif owner.business?
      # TODO: ecosystem-apps/issues/5723 actually add support for businesses in the Permissions::Enforcer check.
      # For now only check if the current user can admin the business.
      @can_create_apps = owner.adminable_by?(current_user)
    elsif owner.archived?
      @can_create_apps = false
    else
      @can_create_apps = Permissions::Enforcer.authorize(
        actor: current_user,
        action: :manage_all_apps,
        subject: owner,
      ).allow?
    end
  end
end
