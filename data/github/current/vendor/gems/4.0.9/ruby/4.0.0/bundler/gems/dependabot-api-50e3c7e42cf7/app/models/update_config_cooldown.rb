# frozen_string_literal: true

# Stores cooldown settings for update configurations
class UpdateConfigCooldown < ApplicationRecord
  class CooldownNotFound < StandardError; end

  belongs_to :update_config

  validates :default_days, :semver_major_days, :semver_minor_days, :semver_patch_days,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def cooldown_settings
    {
      "default-days" => default_days || 0,
      "semver-major-days" => semver_major_days || 0,
      "semver-minor-days" => semver_minor_days || 0,
      "semver-patch-days" => semver_patch_days || 0,
      "include" => Array(include),
      "exclude" => Array(exclude),
    }.compact
  end
end
