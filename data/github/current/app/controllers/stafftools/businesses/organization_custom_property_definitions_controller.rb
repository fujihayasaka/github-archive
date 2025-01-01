# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::OrganizationCustomPropertyDefinitionsController < Stafftools::Businesses::BusinessBaseController
  before_action :ensure_feature_enabled

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
    "stafftools-organization-custom-properties"
  end

  class DefinitionsPayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "definitionsIndexRoute"
    end

    sig { params(definitions: T::Array[CustomProperties::IPropertyDefinition]).void }
    def initialize(definitions:)
      @definitions = definitions
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload
      {
        definitions: @definitions.map do |definition|
          {
            name: definition.property_name,
            required: definition.required,
            defaultValue: definition.default_value,
          }
        end,
      }
    end
  end

  class DefinitionPayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "definitionsShowRoute"
    end

    sig { params(definition: CustomProperties::IPropertyDefinition).void }
    def initialize(definition:)
      @definition = definition
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload
      {
        definition: {
          name: @definition.property_name,
          description: @definition.description,
          allowedValues: @definition.allowed_values,
          defaultValue: @definition.default_value,
          required: @definition.required,
          valueType: @definition.value_type,
        }
      }
    end
  end

  sig { void }
  def index
    definitions = Orgs.domain.custom_properties.get_definitions(this_business)

    respond_with_react(
      title: "Organization property definitions",
      payload: DefinitionsPayload.new(definitions: definitions),
    )
  end

  sig { void }
  def show
    definition_name = params[:id]
    definition = Orgs.domain.custom_properties.get_definition(this_business, definition_name)
    return render_404 unless definition

    respond_with_react(
      title: "Definition for #{definition_name}",
      payload: DefinitionPayload.new(definition: definition),
      page_data: {
        selected_link: :organization_custom_property_definitions,
      },
    )
  end

  private

  sig { void }
  def ensure_feature_enabled
    render_404 unless Orgs.domain.custom_properties.feature_enabled?(this_business)
  end
end
