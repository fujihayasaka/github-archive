# typed: strict
# frozen_string_literal: true

class RepositoriesCustomProperties::AllowedValuesController < ApplicationController
  include GitHub::Memoizer

  depends_on_clusters \
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories

  layout false

  before_action :login_required

  sig { void }
  def show
    return head :not_found unless params[:property_name].present?

    source = current_source
    return head :not_found unless source

    return head :unauthorized unless Repositories.domain.custom_properties.can_see_property_definitions?(current_user, source)

    definition = Repositories.domain.custom_properties.get_definition(source, params[:property_name])

    return head :not_found unless definition
    return head :not_found if definition.allowed_values.nil?

    render json: { allowedValues: definition.allowed_values }
  end

  private

  sig { returns(T.nilable(CustomPropertiesCore::PropertySource)) }
  memoize def current_source
    return nil if params[:owner].present? && params[:enterprise].present?

    if params[:owner].present?
      Organization.find_by(login: params[:owner])
    elsif params[:enterprise].present?
      Business.find_by(slug: params[:enterprise])
    else
      nil
    end
  end

  sig { returns(T.any(User, Symbol, NilClass)) }
  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    current_user
  end

  sig { returns(T.any(User, Business, Symbol, NilClass)) }
  def target_for_conditional_access
    return :no_target_for_conditional_access unless current_source # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_source
  end
end
