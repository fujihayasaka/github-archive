# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

class PermissionsDiffer

  attr_reader :previous_permissions, :new_permissions

  def initialize(previous_permissions:, new_permissions:)
    @previous_permissions = symbolize_values(previous_permissions)
    @new_permissions = symbolize_values(new_permissions)
  end

  def added_permissions
    keys = new_permissions.keys - previous_permissions.keys
    new_permissions.slice(*keys)
  end

  def downgraded_permissions
    keys = (previous_permissions.keys & new_permissions.keys).select do |permission|
      previous_action = previous_permissions[permission]
      previous_ranking = Permission::ACTION_RANKING[previous_action]

      new_action = new_permissions[permission]
      new_ranking = Permission::ACTION_RANKING[new_action]

      previous_ranking > new_ranking
    end

    new_permissions.slice(*keys)
  end

  def removed_permissions
    keys = previous_permissions.keys - new_permissions.keys
    previous_permissions.slice(*keys)
  end

  def unchanged_permissions
    keys = (new_permissions.keys & previous_permissions.keys).keep_if do |permission|
      new_permissions[permission] == previous_permissions[permission]
    end

    new_permissions.slice(*keys)
  end

  def upgraded_permissions
    keys = (previous_permissions.keys & new_permissions.keys).select do |permission|
      previous_action = previous_permissions[permission]
      previous_ranking = Permission::ACTION_RANKING[previous_action]

      new_action = new_permissions[permission]
      new_ranking = Permission::ACTION_RANKING[new_action]

      previous_ranking < new_ranking
    end

    new_permissions.slice(*keys)
  end

  private

  def symbolize_values(permissions)
    permissions.transform_values(&:to_sym)
  end
end
