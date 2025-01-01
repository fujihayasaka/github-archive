# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityCampaigns::CampaignTemplatesTest < GitHub::TestCase
  test "there are some templates" do
    assert_operator 0, :<, SecurityCampaigns::CampaignTemplates::ALL_TEMPLATES.size
  end

  test "the templates all have the required properties" do
    SecurityCampaigns::CampaignTemplates::ALL_TEMPLATES.each do |_, template|
      assert template.name.present?
      assert template.description.present?
      assert template.build_query(true).present?
    end
  end

  test "the queries of all templates are valid" do
    SecurityCampaigns::CampaignTemplates::ALL_TEMPLATES.each do |_, template|
      query = template.build_query(true)
      assert Search::Queries::SecurityCenter::CodeScanningOrgQuery.new(query).is_valid?
    end
  end
end
