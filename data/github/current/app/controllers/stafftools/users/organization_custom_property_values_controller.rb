# typed: true
# frozen_string_literal: true

class Stafftools::Users::OrganizationCustomPropertyValuesController < StafftoolsController
  before_action :ensure_user_exists, :ensure_organization_user, :ensure_business_owned_organization, :ensure_feature_enabled

  depends_on_clusters ApplicationRecord::Mysql1,
  ApplicationRecord::IamAbilities,
  ApplicationRecord::Repositories,
  ApplicationRecord::Collab,
  ApplicationRecord::Mysql2,
  ApplicationRecord::Mysql5,
  ApplicationRecord::NotificationsEntries,
  ApplicationRecord::Billing,
  ApplicationRecord::Spokes,
  ApplicationRecord::Ballast,
  only: [:index]
  depends_on_clusters ApplicationRecord::Copilot, only: [:index], optional: true

  sig { returns(String) }
  def self.react_bundle_name
    "stafftools-organization-custom-properties"
  end

  class ValuesPayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "valuesIndexRoute"
    end

    def initialize(properties:, owner:)
      @properties = properties
      @owner = owner
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload
      {
        owner: @owner,
        properties: @properties
      }
    end
  end

  sig { void }
  def index
    org = this_user
    custom_props = Orgs.domain.custom_properties.values_for_targets([org], value_to_use: :effective, strip_nils: false)[org]
    return render_404 if custom_props.nil?

    respond_with_react(
      title: "Organization property values",
      payload: ValuesPayload.new(properties: custom_props, owner: org.business.slug),
      page_data: {
        selected_link: :organization_custom_property_values,
      },
      layout: "layouts/stafftools/organization/overview",
    )
  end

  private

  sig { void }
  def ensure_organization_user
    render_404 unless this_user&.organization?
  end

  sig { void }
  def ensure_business_owned_organization
    render_404 unless this_user&.business
  end

  sig { void }
  def ensure_feature_enabled
    render_404 unless Orgs.domain.custom_properties.feature_enabled?(this_user)
  end
end
