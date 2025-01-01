# typed: strict
# frozen_string_literal: true

class Orgs::GroupsController < Orgs::Controller
  before_action :repos_groups_enabled

  include GroupSettingsControllerMethods

  protected

  sig { void }
  def repos_groups_enabled
    render_404 unless current_organization&.feature_enabled?(:repos_groups)
  end

  sig { override.returns(Organization) }
  def group_organization
    current_organization
  end

  sig { override.returns(Symbol) }
  def selected_link
    :organization_group_settings
  end

  sig { override.returns(T::Boolean) }
  def read_only?
    true
  end

  sig { override.returns(String) }
  def title_prefix
    ""
  end

  sig { override.returns(String) }
  def base_path
    organization_groups_path
  end
end
