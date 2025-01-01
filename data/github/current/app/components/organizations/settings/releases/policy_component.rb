# typed: true
# frozen_string_literal: true

class Organizations::Settings::Releases::PolicyComponent < ApplicationComponent
  REPOSITORIES_FORM_ID = "releases-policy-repos-form"

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

  sig { returns(T::Array[GitHub::Menu::ButtonComponent]) }
  def release_policy_list
    enable_button = GitHub::Menu::ButtonComponent.new(
      text: "All repositories",
      description: "Require immutable releases for all repositories",
      replace_text: "All repositories",
      checked: config.immutable_releases_enabled_for_all?,
      name: "policy",
      value: Releases::ImmutableOrganizationConfig::ALL,
      type: "submit",
    )
    selected_entities_button = GitHub::Menu::ButtonComponent.new(
      text: "Selected repositories",
      description: "Require immutable releases for specifically selected repositories",
      replace_text: "Selected repositories",
      checked: config.immutable_releases_enabled_for_selected?,
      name: "policy",
      value: Releases::ImmutableOrganizationConfig::SELECTED,
      type: "submit",
    )
    no_policy_button = GitHub::Menu::ButtonComponent.new(
      text: "No policy",
      description: "Each repository chooses whether to make releases immutable",
      replace_text: "No policy",
      checked: config.immutable_releases_enabled_for_none?,
      name: "policy",
      value: Releases::ImmutableOrganizationConfig::NONE,
      type: "submit",
    )

    [enable_button, selected_entities_button, no_policy_button]
  end
end
