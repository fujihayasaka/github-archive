# typed: strict
# frozen_string_literal: true

class Businesses::OrgsCustomPropertiesSettingsController < Businesses::BusinessController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include Orgs::CustomPropertiesHelper
  include CustomPropertiesCore::Errors

  allow_verified_fetch only: [:promote]

  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
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
    org = T.must(organization_from_param)

    definition = Repositories.domain.custom_properties.get_definition(org, params[:property_name])
    return render_404 if definition.nil?

    child_orgs_definitions = Repositories.domain.custom_properties.child_orgs_definitions_by_name(this_business, definition.property_name)

    conflicting_properties = child_orgs_definitions.reject { |d| d.source_id == org.id }

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

    definition = Repositories.domain.custom_properties.get_definition(org, name)

    return render_404 if definition.nil?

    begin
      Repositories.domain.custom_properties.promote_definition(this_business, definition)
      head 201
    rescue ArgumentError => e
      render json: { error: e.message }, status: 400
    end
  end

  private

  sig { void }
  def check_org_exists
    render_404 unless organization_from_param
  end

  sig { returns(T.nilable(::Organization)) }
  memoize def organization_from_param
    this_business.organizations.find_by_login(params[:organization_login])
  end
end
