# typed: true
# frozen_string_literal: true

class Organizations::Settings::Releases::PolicyComponent < ApplicationComponent
  REPOSITORIES_FORM_ID = "releases-policy-repos-form"

  PolicyItem = Struct.new(:label, :description, :value, :checked, keyword_init: true)

  attr_reader :organization

  def initialize(organization:)
    @organization = organization
  end

  sig { returns(::Releases::ImmutableOrganizationConfig) }
  memoize def config
    Releases::ImmutableOrganizationConfig.new(organization)
  end

  sig { returns(Integer) }
  memoize def selected_repo_count
    config.immutable_releases_enforced_repo_ids.count
  end

  sig { returns(T::Array[PolicyItem]) }
  memoize def release_policy_list
    [
      PolicyItem.new(
        label: "All repositories",
        description: "Require immutable releases for all repositories",
        value: Releases::ImmutableOrganizationConfig::ALL,
        checked: config.immutable_releases_enabled_for_all?,
      ),
      PolicyItem.new(
        label: "Selected repositories",
        description: "Require immutable releases for specifically selected repositories",
        value: Releases::ImmutableOrganizationConfig::SELECTED,
        checked: config.immutable_releases_enabled_for_selected?,
      ),
      PolicyItem.new(
        label: "No policy",
        description: "Each repository chooses whether to make releases immutable",
        value: Releases::ImmutableOrganizationConfig::NONE,
        checked: config.immutable_releases_enabled_for_none?,
      ),
    ]
  end

  sig { returns(String) }
  def current_selection_label
    release_policy_list.find(&:checked)&.label || "Select a policy"
  end
end
