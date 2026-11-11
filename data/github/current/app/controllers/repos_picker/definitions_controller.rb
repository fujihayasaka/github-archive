# typed: true
# frozen_string_literal: true

class ReposPicker::DefinitionsController < ApplicationController
  include ReposPicker::CurrentOwnerDependency
  include ReposPicker::DefinitionsPayloadDependency

  depends_on_clusters \
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories

  layout false

  before_action :login_required

  sig { void }
  def index
    return head :not_found unless current_owner || current_enterprise
    return head :not_found if current_owner && current_enterprise

    return head :unauthorized unless can_see_property_definitions?

    if current_owner
      return head :not_found unless T.must(current_owner).organization?
    end

    source = T.cast(current_owner || current_enterprise, CustomPropertiesCore::PropertySource)
    definitions = Repositories.domain.custom_properties.get_definitions(source)

    payload = { definitions: definitions_payload(definitions) }

    if Repositories.domain.custom_properties.external_properties_enabled?(source)
      external_defs = Repositories.domain.custom_properties.get_external_property_definitions(source)

      payload[:namespaces] = namespaced_definitions_payload(external_defs.merge({ "props" => definitions }))
    end

    render json: payload
  end

  private

  sig { returns(T::Boolean) }
  def can_see_property_definitions?
    if current_owner&.organization?
      Repositories.domain.custom_properties.can_see_property_definitions?(current_user, T.cast(current_owner, Organization), cap_filter)
    elsif current_enterprise
      Repositories.domain.custom_properties.can_see_property_definitions?(current_user, T.must(current_enterprise), cap_filter)
    else
      false
    end
  end
end
