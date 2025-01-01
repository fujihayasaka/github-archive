# typed: true
# frozen_string_literal: true

require "test_helper"

class EarlyAccessSubscribersTest < GitHub::TestCase
  include GitHub::SurveyTestHelper

  setup do
    @user = create(:user)
    @org = create(:organization, admin: @user)

    @survey = create(:survey, slug: "hierarchy_and_roadmap")
    @question = create(:survey_question, survey: @survey)

    @membership = EarlyAccessMembership.new(
      actor: @user,
      member: @org,
      feature_slug: "hierarchy_and_roadmap",
      survey: @survey,
    )
  end

  context "#get_subscriber_ids" do
    test "deserializes array of numbers" do
      expected_value = [1, 2, 3]
      key = EarlyAccessSubscribers.cache_key(@membership.feature_slug, @membership.member_id)
      Billing::Kv.store.set(key, expected_value.to_json)

      actual_value = EarlyAccessSubscribers.get_subscriber_ids(@membership.feature_slug, @membership.member_id)

      assert_equal expected_value, actual_value
    end

    test "returns empty array if malformed JSON found in KV" do
      key = EarlyAccessSubscribers.cache_key(@membership.feature_slug, @membership.member_id)
      Billing::Kv.store.set(key, "garbage-values-blahsgkaghdahgidgds")

      actual_value = EarlyAccessSubscribers.get_subscriber_ids(@membership.feature_slug, @membership.member_id)
      assert_equal [], actual_value
    end
  end

  context "#append_subscriber_id" do
    test "stores first user id" do
      EarlyAccessSubscribers.append_subscriber_id(@membership.feature_slug, @membership.member_id, @user.id)

      membership_key = EarlyAccessSubscribers.cache_key(@membership.feature_slug, @membership.member_id)
      actual_value = Billing::Kv.store.get(membership_key).value { nil }

      expected_value = [@user.id].to_json
      assert_equal expected_value, actual_value
    end

    test "appends new user id to existing key" do
      initial_value = [1]
      key = EarlyAccessSubscribers.cache_key(@membership.feature_slug, @membership.member_id)
      Billing::Kv.store.set(key, initial_value.to_json)

      EarlyAccessSubscribers.append_subscriber_id(@membership.feature_slug, @membership.member_id, @user.id)

      membership_key = EarlyAccessSubscribers.cache_key(@membership.feature_slug, @membership.member_id)
      actual_value = Billing::Kv.store.get(membership_key).value { nil }

      expected_value = [1, @user.id].to_json
      assert_equal expected_value, actual_value
    end

    test "de-duplicates values if called with same id multiple times" do
      initial_value = [1]
      key = EarlyAccessSubscribers.cache_key(@membership.feature_slug, @membership.member_id)
      Billing::Kv.store.set(key, initial_value.to_json)

      EarlyAccessSubscribers.append_subscriber_id(@membership.feature_slug, @membership.member_id, @user.id)
      EarlyAccessSubscribers.append_subscriber_id(@membership.feature_slug, @membership.member_id, @user.id)

      membership_key = EarlyAccessSubscribers.cache_key(@membership.feature_slug, @membership.member_id)
      actual_value = Billing::Kv.store.get(membership_key).value { nil }

      expected_value = [1, @user.id].to_json
      assert_equal expected_value, actual_value
    end

    test "stores current value if cache is corrupted" do
      key = EarlyAccessSubscribers.cache_key(@membership.feature_slug, @membership.member_id)
      Billing::Kv.store.set(key, "garbage-values-blahsgkaghdahgidgds")

      EarlyAccessSubscribers.append_subscriber_id(@membership.feature_slug, @membership.member_id, @user.id)

      membership_key = EarlyAccessSubscribers.cache_key(@membership.feature_slug, @membership.member_id)
      actual_value = Billing::Kv.store.get(membership_key).value { nil }

      expected_value = [@user.id].to_json
      assert_equal expected_value, actual_value
    end
  end
end
