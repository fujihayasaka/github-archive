# typed: true
# frozen_string_literal: true

class ReposPicker::DefinitionsController < ApplicationController
  include ReposPicker::CurrentOrganizationDependency
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
    return head :not_found unless current_organization
    return head :unauthorized unless can_see_property_definitions?

    definitions = definitions_manager.get_definitions
    render json: { definitions: definitions_payload(definitions) }
  end

  private

  sig { returns(CustomPropertiesDefinitionsManager) }
  memoize def definitions_manager
    CustomProperties::Public.definitions_manager(T.must(current_organization))
  end

  sig { returns(T::Boolean) }
  def can_see_property_definitions?
    Repositories.domain.custom_properties.can_see_property_definitions?(current_user, T.must(current_organization))
  end
end
