# typed: strict
# frozen_string_literal: true

class Businesses::CustomRoles::EnterprisePresetRolesListComponent < ApplicationComponent
  include GitHub::Memoizer

  sig { returns(Business) }
  attr_reader :business

  sig { returns(T::Hash[Symbol, Primer::SystemArgumentsValue]) }
  attr_reader :system_arguments

  sig do
    params(
      business: Business,
      system_arguments: Primer::SystemArgumentsValue,
    ).void
  end
  def initialize(business:, **system_arguments)
    @business = business
    @system_arguments = system_arguments
  end


  sig { returns(T::Boolean) }
  def render?
    preset_roles.any?
  end

  private

  sig { returns(T::Array[EnterpriseRole]) }
  memoize def preset_roles
    roles = EnterpriseRole.visible_preset_roles(business)
    Role.preload_nested_permissions(roles)
    roles
  end

  sig { returns(T::Array[Organization]) }
  memoize def organizations_representing_all
    business.organizations.order(created_at: :desc).limit(3).to_a
  end
end
