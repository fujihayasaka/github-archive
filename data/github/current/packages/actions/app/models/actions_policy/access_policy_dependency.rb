# typed: false
# frozen_string_literal: true

module ActionsPolicy::AccessPolicyDependency
  extend ActiveSupport::Concern

  included do
    has_one :actions_allowlist, as: :entity, class_name: "ActionsPolicy::Allowlist"
  end

  # Similar to how we use a hierarchy lookup for `#actions_access`, this method
  # determined which level's allowlist settings are more restrictive. We do this
  # by finding using the highest ranking/number according to the
  # restrictiveness.
  #
  # From least restrictive to most restrictive:
  # - 0 = all action types allowed
  # - 1 = github-owned, verified, patterns allowed
  # - 2 = local actions only
  def most_restrictive_allowlist
    [highest_level_allowlist, closest_owner_allowlist, lowest_level_allowlist].compact.max_by do |settings|
      ActionsPolicy::Allowlist.to_rank(settings)
    end
  end

  def most_restrictive_owner_allowlist
    [highest_level_allowlist, closest_owner_allowlist].reject { |allowlist| allowlist == find_allowlist }
      .compact.max_by do |settings|
        ActionsPolicy::Allowlist.to_rank(settings)
      end
  end

  # Predicates for determining this entity's effective policy
  #
  # If the owner only allows local actions, that takes precedence. For each of
  # these methods, we'll take a look at the closest upper level allowlist
  # settings and then fall back on the entity's own.

  def allows_all_actions?
    return false if actions_disabled_at_any_level?
    most_restrictive_allowlist.blank?
  end

  def allows_local_actions_only?
    return false if actions_disabled_at_any_level?
    most_restrictive_allowlist&.local_only?
  end

  def allows_github_owned_actions?
    return false if actions_disabled_at_any_level?
    most_restrictive_allowlist&.github_owned_allowed?
  end

  def allows_verified_actions?
    return false if actions_disabled_at_any_level?
    most_restrictive_allowlist&.verified_allowed?
  end

  def allows_specific_actions_patterns?
    return false if actions_disabled_at_any_level?
    most_restrictive_allowlist&.specified_patterns?
  end

  def allows_specified_actions?
    return false if actions_disabled_at_any_level?
    most_restrictive_allowlist&.includes_specific_actions?
  end

  # Other helpful predicates
  def highest_level_specified_actions?
    highest_level_allowlist&.includes_specific_actions? && highest_level_allowlist.entity != self
  end

  def owner_allows_local_actions_only?
    most_restrictive_owner_allowlist.present? && most_restrictive_owner_allowlist.local_only?
  end

  def owner_allows_specified_actions_only?
    most_restrictive_owner_allowlist&.includes_specific_actions?
  end

  def owner_restricts_allowed_actions?
    most_restrictive_owner_allowlist.present?
  end

  # Policy management
  def enable_local_actions_only
    find_allowlist.enable_local_only
  end

  def clear_allowlist_settings
    actions_allowlist&.destroy
  end

  def enable_specified_actions_only(**options)
    find_allowlist.enable_specified_actions(**options)
  end

  def actions_disabled_at_any_level?
    async_actions_disabled_at_any_level?.sync
  end

  def async_actions_disabled_at_any_level?
    async_configuration_owner.then do |_owner|
      actions_disabled? || actions_disabled_by_owner?
    end
  end

  private

  def find_allowlist
    return @_allowlist if defined?(@_allowlist)
    @_allowlist = ActionsPolicy::Allowlist.find_by(entity: self) ||
      ActionsPolicy::Allowlist.new(entity: self)
  end
end
