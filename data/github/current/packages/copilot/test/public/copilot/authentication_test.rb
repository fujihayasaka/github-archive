# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::AuthenticationTest < GitHub::TestCase
  include DogstatsTestHelpers
  include CopilotTestHelper # automatically disables Copilot feature flags
  include GitHub::QueryAssertionTestHelpers

  fixtures do
    @user = create(:user)
    @copilot_user = Copilot::User.new(@user).freeze
  end

  setup do
    Copilot.redis.flushdb
  end

  context "latest_for_user" do
    test "defaults to nil" do
      assert_nil Copilot::Authentication.latest_for_user(@copilot_user)
    end

    test "returns the proper details" do
      details = create_authentication(@user)
      authentication = Copilot::Authentication.latest_for_user(@copilot_user)
      refute_nil authentication
      assert_equal details.editor_details, T.must(authentication).editor_details
      assert_equal details.ip_address, T.must(authentication).ip_address
      assert_equal details.timestamp, T.must(authentication).timestamp
      assert_equal details.user_id, T.must(authentication).user_id
    end
  end

  context "latest_for_user_id" do
    test "defaults to nil" do
      assert_nil Copilot::Authentication.latest_for_user_id(@user.id)
    end

    test "returns the proper details" do
      details = create_authentication(@user)
      authentication = Copilot::Authentication.latest_for_user_id(@user.id)
      refute_nil authentication
      assert_equal details.editor_details, T.must(authentication).editor_details
      assert_equal details.ip_address, T.must(authentication).ip_address
      assert_equal details.timestamp, T.must(authentication).timestamp
      assert_equal details.user_id, T.must(authentication).user_id
    end
  end

  context "latest_for_user_ids" do
    test "defaults to nil" do
      assert_empty Copilot::Authentication.latest_for_user_ids([@user.id])
      assert_empty Copilot::Authentication.latest_for_user_ids([])
    end

    test "only returns authentications for users who have activity" do
      other_user = create(:user)
      other_other_user = create(:user)

      create_authentication(@user)
      create_authentication(other_user)

      authentications = Copilot::Authentication.latest_for_user_ids([@user.id, other_user.id, other_other_user.id])
      assert_equal 2, authentications.size
      assert_includes authentications.map(&:user_id), @user.id
      assert_includes authentications.map(&:user_id), other_user.id
    end

    test "returns the proper details" do
      other_user = create(:user)

      details = create_authentication(@user)
      other_details = create_authentication(other_user)

      authentications = Copilot::Authentication.latest_for_user_ids([@user.id, other_user.id])

      assert_equal 2, authentications.size
      user_details = authentications.find { |a| a.user_id == @user.id }
      other_user_details = authentications.find { |a| a.user_id == other_user.id }

      refute_nil user_details
      refute_nil other_user_details

      assert_equal details.editor_details, T.must(user_details).editor_details
      assert_equal details.ip_address, T.must(user_details).ip_address
      assert_equal details.timestamp, T.must(user_details).timestamp
      assert_equal details.user_id, T.must(user_details).user_id

      assert_equal other_details.editor_details, T.must(other_user_details).editor_details
      assert_equal other_details.ip_address, T.must(other_user_details).ip_address
      assert_equal other_details.timestamp, T.must(other_user_details).timestamp
      assert_equal other_details.user_id, T.must(other_user_details).user_id
    end
  end

  context "for_organization" do
    test "loads all users in the org" do
      org = create(:copilot_for_business_enabled_organization)
      copilot_org = Copilot::Organization.new(org)

      5.times do |i|
        user = create(:user)
        org.add_member(user)
        create_authentication(user) if i.even?
      end
      last_user = create(:user)
      org.add_member(last_user)
      org.publicize_member(last_user)
      assert org.reload.members.include?(last_user)

      create_authentication(last_user)

      authentications = Copilot::Authentication.for_organization(copilot_org)
      assert_equal 4, authentications.size

      ## removing a member does not delete their redis key, but it does remove them from the org
      perform_enqueued_jobs(only: [RevokeOrgMembershipAbilitiesJob]) do
        org.remove_member!(org.members.last)
      end
      org.reload

      refute org.members.include?(last_user)

      copilot_org = Copilot::Organization.new(org)
      authentications = Copilot::Authentication.for_organization(copilot_org)
      assert_equal 3, authentications.size

      ## the redis key is still there
      assert Copilot.redis.hkeys("last_authenticated:#{last_user.id}").any?

    end
  end

  def create_authentication(user)
    editor_details = "#{Faker::App.semantic_version}/#{Faker::App.semantic_version}"
    ip_address = Faker::Internet.ip_v4_address
    timestamp = Time.now.utc.iso8601

    Copilot.redis.hmset(
      "last_authenticated:#{user.id}",
      "editor_details", editor_details,
      "ip_address", ip_address,
      "timestamp", timestamp,
      "user_id", user.id,
    )

    Copilot::Authentication.new(
      editor_details: editor_details,
      ip_address: ip_address,
      timestamp: Time.parse(timestamp).utc,
      user_id: user.id,
    )
  end
end
