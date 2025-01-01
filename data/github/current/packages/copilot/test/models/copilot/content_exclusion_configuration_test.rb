# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotContentExclusionConfiguration < GitHub::TestCase
  include CopilotTestHelper

  context "validations" do
    test "is valid for Organization, Repository and Business" do
      entity = create(:copilot_content_exclusion_configuration, :organization)
      assert entity.resource.is_a?(::Organization)

      entity = create(:copilot_content_exclusion_configuration, :repository)
      assert entity.resource.is_a?(::Repository)

      entity = create(:copilot_content_exclusion_configuration, :business)
      assert entity.resource.is_a?(::Business)
    end

    test "only allow for Organization, Repository and Business" do
      config = build(:copilot_content_exclusion_configuration, resource: create(:user))
      refute config.valid?
    end

    test "ensures document validity for Organizations" do
      config = build(:copilot_content_exclusion_configuration, :organization, document: "test:")
      refute config.valid?
      assert_equal "Error on line 1, column 6: Expecting an array of rule configurations", config.errors.first.message
    end

    test "ensures document validity for Repositories" do
      config = build(:copilot_content_exclusion_configuration, :repository, document: "test:")
      refute config.valid?
      assert_equal "Error on line 1, column 1: Expecting an array of paths", config.errors.first.message
    end

    test "ensures document validity for Businesses" do
      config = build(:copilot_content_exclusion_configuration, :business, document: "test:")
      refute config.valid?
      assert_equal "Error on line 1, column 6: Expecting an array of rule configurations", config.errors.first.message
    end

    test "ensure org_id is set when creating records" do
      entity = create(:copilot_content_exclusion_configuration, :repository)
      refute_nil entity.organization_id
      assert entity.organization.is_a?(::Organization)
    end

    test "honor the organization_id if it set as part of the create" do
      org = create(:organization)
      entity = create(:copilot_content_exclusion_configuration, :repository, organization: org)
      assert entity.organization.is_a?(::Organization)
      assert entity.organization_id == org.id
    end
  end

  context "allow_text_based_rules" do
    test "if org is not feature flagged, don't allow the inclusion rules for repositories" do
      entity = build(:copilot_content_exclusion_configuration, :repository, document: <<~YAML)
      - ifNoneMatch: [/abc/]
      - "*.md"
      YAML
      refute entity.valid?
    end

    test "if org is feature flagged, allow the inclusion rules for repositories" do
      org = create(:organization)
      GitHub.flipper[:copilot_allow_text_based_content_exclusions].enable(org)
      repo = create(:repository, owner: org)
      entity = create(:copilot_content_exclusion_configuration, :repository, document: <<~YAML, resource: repo)
      - ifNoneMatch: [/abc/]
      - "*.md"
      YAML
      assert entity.valid?
    end

    test "if org is not feature flagged, don't allow the inclusion rules for organizations" do
      entity = build(:copilot_content_exclusion_configuration, :organization, document: <<~YAML)
      repo:
      - ifNoneMatch: [/abc/]
      - "*.md"
      YAML
      refute entity.valid?
    end

    test "if org is feature flagged, allow the inclusion rules for organizations" do
      org = create(:organization)
      GitHub.flipper[:copilot_allow_text_based_content_exclusions].enable(org)
      entity = create(:copilot_content_exclusion_configuration, :organization, document: <<~YAML, resource: org)
      repo:
      - ifNoneMatch: [/abc/]
      - "*.md"
      YAML
      assert entity.valid?
    end

    test "if business is feature flagged, allow the inclusion rules for businesses" do
      business = create(:business)
      GitHub.flipper[:copilot_allow_text_based_content_exclusions].enable(business)
      entity = create(:copilot_content_exclusion_configuration, :business, document: <<~YAML, resource: business)
      repo:
      - ifNoneMatch: [/abc/]
      - "*.md"
      YAML
      assert entity.valid?
    end
  end

end if GitHub.copilot_enabled?
