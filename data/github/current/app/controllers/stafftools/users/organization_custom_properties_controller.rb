# typed: strict
# frozen_string_literal: true

class Stafftools::Users::OrganizationCustomPropertiesController < StafftoolsController
  before_action :ensure_user_exists

  include ReactHelper

  depends_on_clusters \
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:index, :show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show],
    optional: true

  sig { returns(String) }
  def self.react_bundle_name
    "stafftools-custom-properties"
  end

  sig { void }
  def index
    return render_404 unless this_user.organization?

    definitions = CustomProperties::Public.definitions_manager(this_user).get_definitions
    definitions_payload = definitions.map do |definition|
      {
        name: definition.property_name,
        required: definition.required,
        defaultValue: definition.default_value,
        managedBySlug: definition.source_type == "business" ? this_user.business.slug : nil
      }
    end

    render_react_app(
      title: "Custom property definitions",
      payload: { definitions: definitions_payload },
      layout: "layouts/stafftools/organization/overview",
      ssr: false,
    )
  end

  sig { void }
  def show
    return render_404 unless this_user.organization?

    definition_name = params[:id]

    definitions = CustomProperties::Public.definitions_manager(this_user).get_definitions
    definition = definitions.find { |d| d.property_name == definition_name }

    return render_404 unless definition

    render_react_app(
      title: "Definition for #{definition_name}",
      payload: { definition: {
        name: definition.property_name,
        description: definition.description,
        allowedValues: definition.allowed_values,
        defaultValue: definition.default_value,
        required: definition.required,
        valueType: definition.value_type,
      } },
      page_data: {
        selected_link: :organization_custom_properties
      },
      layout: "layouts/stafftools/organization/overview",
      ssr: false,
    )
  end
end
