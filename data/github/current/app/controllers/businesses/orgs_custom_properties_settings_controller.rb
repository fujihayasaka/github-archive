# typed: strict
# frozen_string_literal: true

class Businesses::OrgsCustomPropertiesSettingsController < Businesses::BusinessController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include Orgs::CustomPropertiesHelper
  include CustomProperties::Errors

  allow_verified_fetch only: [:promote]

  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :check_business_properties_enabled
  before_action :check_org_exists


  sig { returns(String) }
  def self.react_bundle_name
    "custom-properties"
  end

  javascript_bundle :settings

  layout "react_business"

  depends_on_clusters \
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
  only: [:show]

  sig { void }
  def show
    add_client_feature_flag([:enterprise_custom_properties_list]) do
      CustomProperties::Public.enterprise_properties_list_enabled?(this_business)
    end
    add_client_feature_flag([:enterprise_custom_properties_promotion]) do
      this_business.feature_enabled?(:enterprise_custom_properties_promotion)
    end

    org = T.must(organization_from_param)

    definition = CustomProperties::Public.definitions_manager(org).get_definition(params[:property_name])
    return render_404 if definition.nil?

    conflicting_properties = CustomProperties::Public
      .business_definitions_manager(this_business)
      .child_orgs_definitions_by_name(definition.property_name)
      .reject { |d| d.source_id == org.id }

    title = "Custom properties · #{this_business.name} · #{org.display_login} · #{definition.property_name}"

    render_react_app(
      disable_ssr: true,
      payload: {
        definition: definition_payload(definition),
        business: {
          name: this_business.name,
          slug: this_business.slug,
        },
        orgConflicts: org_conflicts_payload(definition.property_name, conflicting_properties),
        propertyNames: [],
        canManageProperty: org.can_manage_organization_custom_properties_definitions?(current_user),
      },
      title: title,
      page_data: { selected_link: :business_custom_properties_settings, sidebar: :policies },
    )
  end

  sig { void }
  def promote # rubocop:disable GitHub/UseRestfulActions
    org = T.must(organization_from_param)

    name = params[:property_name]
    org_manager = CustomProperties::Public.definitions_manager(org)
    definition = org_manager.get_definition(name)
    return render_404 if definition.nil?

    business_manager = CustomProperties::Public.business_definitions_manager(this_business)

    begin
      business_manager.promote_definition(definition)
      head 201
    rescue ArgumentError => e
      render json: { error: e.message }, status: 400
    end
  end

  private

  sig { void }
  def check_business_properties_enabled
    render_404 unless CustomProperties::Public.enterprise_properties_enabled?(this_business)
  end

  sig { void }
  def check_org_exists
    render_404 unless organization_from_param
  end

  sig { returns(T.nilable(::Organization)) }
  memoize def organization_from_param
    this_business.organizations.find_by_login(params[:organization_login])
  end
end
