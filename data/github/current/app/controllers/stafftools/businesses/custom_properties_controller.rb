# typed: strict
# frozen_string_literal: true

class Stafftools::Businesses::CustomPropertiesController < Stafftools::Businesses::BusinessBaseController
  include ReactHelper

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:index, :show]

  sig { returns(String) }
  def self.react_bundle_name
    "stafftools-custom-properties"
  end

  sig { void }
  def index
    definitions = CustomProperties::Public.business_definitions_manager(this_business).get_definitions
    definitions_payload = definitions.map do |definition|
      {
        name: definition.property_name,
        required: definition.required,
        defaultValue: definition.default_value,
      }
    end

    render_react_app(
      title: "Custom property definitions",
      payload: { definitions: definitions_payload },
      ssr: false,
    )
  end

  sig { void }
  def show
    definition_name = params[:id]

    definition = CustomProperties::Public.business_definitions_manager(this_business).get_definition(definition_name)

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
        selected_link: :custom_properties
      },
      ssr: false,
    )
  end
end
