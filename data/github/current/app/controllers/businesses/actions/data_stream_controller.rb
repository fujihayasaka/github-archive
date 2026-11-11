# typed: strict
# frozen_string_literal: true

class Businesses::Actions::DataStreamController < Businesses::BusinessController
  include Actions::DataStream
  include Actions::LargerRunnersHelper

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

  sig { override.returns(Business) }
  def data_stream_entity
    this_business
  end

  sig { override.returns(Integer) }
  def data_stream_owner_id
    this_business.id
  end

  sig { override.returns(Symbol) }
  def data_stream_owner_type
    :OWNER_TYPE_ENTERPRISE
  end

  sig { override.returns(String) }
  def data_stream_base_path
    settings_actions_data_stream_enterprise_path(this_business)
  end

  sig { override.void }
  def data_stream_admin_required
    business_owner_required
  end

  sig { override.returns(String) }
  def data_stream_layout
    "layouts/settings/enterprise_actions_settings_react"
  end

  sig { override.returns(Symbol) }
  def data_stream_selected_link
    :enterprise_actions_settings_data_stream
  end

  sig { override.returns(T::Hash[Symbol, T.untyped]) }
  def data_stream_page_data
    { selected_link: data_stream_selected_link, sidebar: :policies }
  end

  sig { override.returns(T::Hash[Symbol, T.untyped]) }
  def data_stream_extra_render_options
    {
      layout_locals_generator: -> { { should_display_custom_images_tab: is_custom_images_enabled?(entity: this_business) } },
    }
  end
end
