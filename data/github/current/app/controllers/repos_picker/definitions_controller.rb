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

    definitions = Repositories.domain.custom_properties.get_definitions(T.cast(current_owner || current_enterprise, ::CustomProperties::PropertySource))

    render json: { definitions: definitions_payload(definitions) }
  end

  private

  sig { returns(T::Boolean) }
  def can_see_property_definitions?
    if current_owner&.organization?
      Repositories.domain.custom_properties.can_see_property_definitions?(current_user, T.cast(current_owner, Organization))
    elsif current_enterprise
      Repositories.domain.custom_properties.can_see_property_definitions?(current_user, T.must(current_enterprise))
    else
      false
    end
  end
end
