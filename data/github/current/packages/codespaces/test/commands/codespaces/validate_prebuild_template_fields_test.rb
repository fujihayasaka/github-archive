# typed: true
# frozen_string_literal: true

require "test_helper"

class ValidatePrebuildTemplateFieldsTest < GitHub::TestCase
  include CodespacesPlanFixtures

  test "raises error with all messages when prebuild template is invalid" do
    template = build(:codespace_prebuild_template)

    args = {
      repository: template.repository,
      vscs_target: "wrong",
      vscs_target_url: template.vscs_target_url,
      location: template.location,
      oid: template.oid,
      branch: template.branch
    }

    exception = assert_raises Codespaces::ValidatePrebuildTemplateFields::InvalidPrebuildTemplate do
      Codespaces::ValidatePrebuildTemplateFields.call(**args)
    end

    assert_includes exception.message, "Plan No plan found for location and vscs_target"
  end

  test "does not raise error when an organization repository has codespace access" do
    template = build(:codespace_prebuild_template)

    args = {
      repository: template.repository,
      vscs_target: template.vscs_target,
      vscs_target_url: template.vscs_target_url,
      location: template.location,
      oid: template.oid,
      branch: template.branch
    }

    Codespaces::ValidatePrebuildTemplateFields.call(**args)
  end
end
