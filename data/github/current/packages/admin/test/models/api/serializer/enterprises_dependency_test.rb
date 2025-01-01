# typed: true
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class BusinessSerializersTest < Api::SerializerTestCase
  include PageHelper

  fixtures do
    @admin = create :user
    @business = create :business,
                       owners: [@admin],
                       description: Faker::Lorem.sentence,
                       website_url: Faker::Internet.url
    @upload = create :enterprise_installation_user_accounts_upload,
      business: @business
  end

  context "#business_hash" do
    test "payload is valid" do
      output = T.unsafe(self).business(@business)
      assert output.key?("name")
      assert output.key?("node_id")
      assert output.key?("avatar_url")
      assert output.key?("description")
    end

    test "returns nil when no business" do
      assert_nil T.unsafe(self).business(nil)
    end

    test "returns business data" do
      output = T.unsafe(self).business(@business)

      assert_equal @business.name, output["name"]
      assert_equal @business.id, output["id"]
      assert_equal @business.global_relay_id, output["node_id"]
      assert_equal @business.slug, output["slug"]
      assert_equal @business.created_at.to_time.utc.xmlschema, output["created_at"]
      assert_equal @business.updated_at.to_time.utc.xmlschema, output["updated_at"]
      assert_equal @business.website_url, output["website_url"]
      assert_equal @business.description, output["description"]
      assert_equal "#{GitHub.url}/enterprises/#{@business}", output["html_url"]
    end
  end

  context "#enterprise_installation_user_accounts_upload_hash" do
    test "payload is valid" do
      output = T.unsafe(self).enterprise_installation_user_accounts_upload(@upload)
      assert output.key?("name")
      assert output.key?("uploader")
      assert output.key?("content_type")
      assert output.key?("state")
    end

    test "returns nil when no upload" do
      assert_nil T.unsafe(self).enterprise_installation_user_accounts_upload(nil)
    end

    test "returns upload data" do
      output = T.unsafe(self).enterprise_installation_user_accounts_upload(@upload)

      assert_equal @upload.id, output["id"]
      assert_equal @upload.name, output["name"]
      assert_equal @upload.content_type, output["content_type"]
      assert_equal @upload.state, output["state"]
      assert_equal @upload.size, output["size"]
      assert_equal @upload.created_at.to_time.utc.xmlschema, output["created_at"]
      assert_equal @upload.updated_at.to_time.utc.xmlschema, output["updated_at"]
      assert_equal @upload.sync_state, output["sync_state"]
      assert_equal "#{GitHub.api_url}/businesses/#{@business.slug}/user-accounts-uploads/#{@upload.id}", output["url"]
    end
  end
end
