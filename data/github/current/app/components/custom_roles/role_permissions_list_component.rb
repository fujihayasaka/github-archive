# typed: strict
# frozen_string_literal: true

module CustomRoles
  class RolePermissionsListComponent < ApplicationComponent
    sig { returns(String) }
    attr_reader :title

    sig { returns(Symbol) }
    attr_reader :icon

    sig { returns(T::Hash[String, T::Array[String]]) }
    attr_reader :permissions_by_category

    sig { returns(T::Hash[String, T::Array[String]]) }
    attr_reader :base_role_permissions_by_category

    sig { returns(T.nilable(String)) }
    attr_reader :base_role_name

    sig { returns(T::Hash[Symbol, Primer::SystemArgumentsValue]) }
    attr_reader :system_arguments

    sig do
      params(
        title: String,
        icon: Symbol,
        permissions_by_category: T::Hash[String, T::Array[String]],
        base_role_permissions_by_category: T::Hash[String, T::Array[String]],
        base_role_name: T.nilable(String),
        system_arguments: Primer::SystemArgumentsValue,
      ).void
    end
    def initialize(
      title:,
      icon:,
      permissions_by_category: {}, # Non-base role permissions
      base_role_permissions_by_category: {},
      base_role_name: nil,
      **system_arguments
    )
      @title = title
      @icon = icon
      @permissions_by_category = permissions_by_category
      @base_role_permissions_by_category = base_role_permissions_by_category
      @base_role_name = base_role_name
      @system_arguments = system_arguments
    end

    sig { returns(T::Boolean) }
    def render?
      !!base_role_name || has_base_role_permissions? || has_permissions?
    end

    sig { returns(T::Boolean) }
    def has_base_role_permissions?
      base_role_permissions_by_category.present?
    end

    sig { returns(T::Boolean) }
    def has_permissions?
      permissions_by_category.present?
    end

    # Returns a categorized list of permissions for display.
    # If permissions are empty, it will return the base role permissions.
    # If no base role permissions are provided, we return an empty hash.
    sig { returns(T::Hash[String, T::Array[String]]) }
    def permissions_by_category_for_display
      has_permissions? ? permissions_by_category : base_role_permissions_by_category
    end
  end
end
