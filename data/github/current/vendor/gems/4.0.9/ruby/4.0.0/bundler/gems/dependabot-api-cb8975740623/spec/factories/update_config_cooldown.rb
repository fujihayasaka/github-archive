# frozen_string_literal: true

FactoryBot.define do
  factory :update_config_cooldown do
    update_config
    default_days { 0 }
    semver_major_days { 0 }
    semver_minor_days { 0 }
    semver_patch_days { 0 }
    include { [] }
    exclude { [] }
  end
end
