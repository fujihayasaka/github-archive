# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::EnablementPolicyInputPresenterTest < GitHub::TestCase
  fixtures do
    @business = create(:business)
  end

  test "serializes correct default all" do
    result = Codespaces::EnablementPolicyInputPresenter.new(business: @business, enabled_count: 0).serialize
    assert_equal [
      {
        text: "Enable for all organizations",
        description: "All organizations, including any created in the future, may use GitHub Codespaces.",
        replace_text: "Enable for all organizations",
        confirm_message: "This will enable codespaces for all organizations.",
        checked: true,
        name: "enablement",
        value: Codespaces::EnablementPolicyInputPresenter::ALL_ENTITIES,
        type: "submit",
        disabled: false
      },
      {
        text: "Enable for specific organizations",
        description: "Only specifically-selected organizations and public repositories may use GitHub Codespaces.",
        replace_text: "Enable for specific organizations",
        confirm_message: "Any codespaces associated with private or internal repositories in the unselected organizations will be deleted.",
        checked: false,
        name: "enablement",
        value: Codespaces::EnablementPolicyInputPresenter::SELECTED_ENTITIES,
        type: "submit",
        disabled: false
      },
      {
        text: "Disabled",
        description: "Only public repositories within this enterprise may use GitHub Codespaces.",
        replace_text: "Disabled",
        confirm_message: "All codespaces from internal and private repositories within your enterprise will be deleted.",
        checked: false,
        name: "enablement",
        value: Codespaces::EnablementPolicyInputPresenter::DISABLED,
        type: "submit",
        disabled: false
      },
    ], result
  end

  test "renders a form with the correct input with correct input selected" do
    Codespaces::BusinessDelegator.new(@business).enable_codespaces_for_selected_organizations!([])
    result = Codespaces::EnablementPolicyInputPresenter.new(business: @business, enabled_count: 1).serialize
    assert_equal [
      {
        text: "Enable for all organizations",
        description: "All organizations, including any created in the future, may use GitHub Codespaces.",
        replace_text: "Enable for all organizations",
        confirm_message: "This will enable codespaces for all organizations.",
        checked: false,
        name: "enablement",
        value: Codespaces::EnablementPolicyInputPresenter::ALL_ENTITIES,
        type: "submit",
        disabled: false
      },
      {
        text: "Enable for specific organizations",
        description: "Only specifically-selected organizations and public repositories may use GitHub Codespaces.",
        replace_text: "Enable for specific organizations",
        confirm_message: "Any codespaces associated with private or internal repositories in the unselected organizations will be deleted.",
        checked: true,
        name: "enablement",
        value: Codespaces::EnablementPolicyInputPresenter::SELECTED_ENTITIES,
        type: "submit",
        disabled: false
      },
      {
        text: "Disabled",
        description: "Only public repositories within this enterprise may use GitHub Codespaces.",
        replace_text: "Disabled",
        confirm_message: "All codespaces from internal and private repositories within your enterprise will be deleted.",
        checked: false,
        name: "enablement",
        value: Codespaces::EnablementPolicyInputPresenter::DISABLED,
        type: "submit",
        disabled: false
      },
    ], result
  end

  test "renders a form with the disabled inputs" do
    Codespaces::BusinessDelegator.new(@business).enable_codespaces_for_selected_organizations!([])
    result = Codespaces::EnablementPolicyInputPresenter.new(business: @business, enabled_count: 1, disable_form: true).serialize
    assert_equal [
      {
        text: "Enable for all organizations",
        description: "All organizations, including any created in the future, may use GitHub Codespaces.",
        replace_text: "Enable for all organizations",
        confirm_message: "This will enable codespaces for all organizations.",
        checked: false,
        name: "enablement",
        value: Codespaces::EnablementPolicyInputPresenter::ALL_ENTITIES,
        type: "submit",
        disabled: true
      },
      {
        text: "Enable for specific organizations",
        description: "Only specifically-selected organizations and public repositories may use GitHub Codespaces.",
        replace_text: "Enable for specific organizations",
        confirm_message: "Any codespaces associated with private or internal repositories in the unselected organizations will be deleted.",
        checked: true,
        name: "enablement",
        value: Codespaces::EnablementPolicyInputPresenter::SELECTED_ENTITIES,
        type: "submit",
        disabled: true
      },
      {
        text: "Disabled",
        description: "Only public repositories within this enterprise may use GitHub Codespaces.",
        replace_text: "Disabled",
        confirm_message: "All codespaces from internal and private repositories within your enterprise will be deleted.",
        checked: false,
        name: "enablement",
        value: Codespaces::EnablementPolicyInputPresenter::DISABLED,
        type: "submit",
        disabled: false
      },
    ], result
  end
end unless GitHub.enterprise?
