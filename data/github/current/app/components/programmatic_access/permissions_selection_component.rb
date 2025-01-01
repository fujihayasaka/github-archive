# typed: true
# frozen_string_literal: true

class ProgrammaticAccess::PermissionsSelectionComponent < ApplicationComponent
  attr_reader :view, :current_target
  delegate :programmatic_actor, to: :view

  renders_one :subhead, -> (**system_arguments) do
    Primer::Beta::Subhead.new(**system_arguments)
  end

  renders_one :description, -> (**system_arguments) do
    opts = {
      mb: 4,
      tag: :p
    }.merge(system_arguments)
    Primer::BaseComponent.new(**T.unsafe(**opts))
  end

  renders_one :additional_settings

  def initialize(view:, hide_repository_permissions: false, current_target: nil)
    @view = view # Instance of Integrations::PermissionsView
    @hide_repository_permissions = hide_repository_permissions
    @current_target = current_target
  end

  def show_repository_permissions?
    return true if integration_view?

    !@hide_repository_permissions
  end

  def show_organization_permissions?
    return true if integration_view?

    current_target.organization?
  end

  def show_enterprise_permissions?
    return false unless integration_view?

    installation_management_feature_enabled?
  end

  def show_user_permissions?
    return true if integration_view?

    current_target.user?
  end

  def integration_view?
    view.integration.present?
  end

  def edit_view?
    programmatic_actor.persisted?
  end

  def installation_management_feature_enabled?
    result = current_user&.feature_enabled?(:enterprise_app_installation_management) ||
      view.integration.owner.feature_enabled?(:enterprise_app_installation_management) ||
      current_user&.enterprise_managed_business&.feature_enabled?(:enterprise_app_installation_management)

    return result if result

    associated_business = if view.integration.owner.is_a?(Business)
      view.integration.owner
    elsif view.integration.owner.is_a?(Organization)
      view.integration.owner.business
    end
    return false unless associated_business

    associated_business.feature_enabled?(:enterprise_app_installation_management)
  end
end
