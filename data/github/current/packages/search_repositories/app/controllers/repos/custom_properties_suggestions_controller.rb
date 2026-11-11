# typed: strict
# frozen_string_literal: true

class Repos::CustomPropertiesSuggestionsController < ApplicationController
  include Orgs::CustomPropertiesHelper

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::IamAbilities

  before_action :login_required
  before_action :ff_enabled

  sig { void }
  def index
    if source.is_a?(Organization)
      single_organization = source
    else
      common_enterprise = source
    end

    render json: {
      definitions: definitions_payload(definitions),
      enterprise: common_enterprise ? { name: common_enterprise.display_login } : nil,
      organization: single_organization ? { login: single_organization.display_login } : nil,
    }
  end

  private

  sig { returns(T::Array[String]) }
  memoize def logins
    params.fetch(:orgs, "").split(",")
  end


  sig { returns(T.any(Business, Organization, NilClass)) }
  memoize def source
    ::Search::Repositories.get_common_source(logins)
  end

  sig { returns(T::Array[CustomPropertiesCore::IPropertyDefinition]) }
  def definitions
    definitions_source = source  # Make Sorbet happy
    return [] unless definitions_source.present?
    return [] unless ::Repositories.domain.custom_properties.can_see_property_definitions?(current_user, definitions_source)

    ::Repositories.domain.custom_properties.get_definitions(definitions_source)
  end

  sig { void }
  def ff_enabled
    render_404 unless FeatureFlag.vexi.enabled?(:repos_finder_suggest_properties, current_user, default: false)
  end

  sig { returns(T.any(Organization, Business, Symbol)) }
  def target_for_conditional_access
    target = source
    return target if target.present?
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
