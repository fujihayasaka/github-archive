# typed: strict
# frozen_string_literal: true

class Orgs::ActionsSettings::DataStreamController < Orgs::Controller
  include Actions::DataStream

  before_action :ensure_trade_restrictions_allows_org_settings_access

  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    only: [:index, :show, :new_sink]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show, :new_sink],
    optional: true

  sig { returns(String) }
  def self.react_bundle_name
    "actions-data-stream"
  end

  private

  sig { override.returns(Organization) }
  def data_stream_entity
    current_organization
  end

  sig { override.returns(Integer) }
  def data_stream_owner_id
    current_organization.id
  end

  sig { override.returns(Symbol) }
  def data_stream_owner_type
    :OWNER_TYPE_ORGANIZATION
  end

  sig { override.returns(String) }
  def data_stream_base_path
    settings_org_actions_data_stream_path(current_organization)
  end

  sig { override.void }
  def data_stream_admin_required
    organization_admin_required
  end

  sig { override.returns(String) }
  def data_stream_layout
    "layouts/settings/actions_org_react"
  end

  sig { override.returns(Symbol) }
  def data_stream_selected_link
    :organization_actions_settings_data_stream
  end

  sig { override.returns(T::Hash[Symbol, T.untyped]) }
  def data_stream_page_data
    { selected_link: data_stream_selected_link }
  end

  sig { override.returns(T::Hash[Symbol, T.untyped]) }
  def data_stream_extra_render_options
    {}
  end
end
