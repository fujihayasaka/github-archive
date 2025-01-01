# typed: true
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class EnterpriseTeamsSerializersTest < Api::SerializerTestCase
  include PageHelper

  fixtures do
    @admin = create :user
    @business = create :business,
                       owners: [@admin]
    @enterprise_team = create :enterprise_team,
                        business: @business
  end

  context "#enterprise_team_hash" do
    test "payload is valid" do
      output = T.unsafe(self).enterprise_team(@enterprise_team)
      assert output.key?("name")
      assert output.key?("id")
      assert output.key?("slug")
      assert output.key?("sync_to_organizations")
      assert output.key?("url")
      assert output.key?("html_url")
      assert output.key?("group_id")
      assert output.key?("members_url")
      assert output.key?("created_at")
      assert output.key?("updated_at")
    end

    test "returns nil when no business" do
      assert_nil T.unsafe(self).enterprise_team(nil)
    end

    test "returns business data" do
      output = T.unsafe(self).enterprise_team(@enterprise_team)
      team_api_path = "/enterprises/#{@enterprise_team.business_id}/teams/#{@enterprise_team.id}"


      assert_equal @enterprise_team.name, output["name"]
      assert_equal @enterprise_team.id, output["id"]
      assert_equal @enterprise_team.slug, output["slug"]
      assert_equal @enterprise_team.sync_to_organizations, output["sync_to_organizations"]
      assert_equal url(team_api_path), output["url"]
      assert_nil output["group_id"]
      assert_equal "#{GitHub.url}/enterprises/#{@enterprise_team.business.slug}/teams/#{@enterprise_team.slug}", output["html_url"]
      assert_equal url("#{team_api_path}/members{/member}"), output["members_url"]
      assert_equal @enterprise_team.created_at.to_time.utc.xmlschema, output["created_at"]
      assert_equal @enterprise_team.created_at.to_time.utc.xmlschema, output["updated_at"]
    end
  end
end
