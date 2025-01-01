# typed: false
# frozen_string_literal: true

require "test_helper"

class TwoFactorRequirementMetadataTest < GitHub::TestCase
  fixtures do
    @non_2fa_user1 = create(:user)
    @non_2fa_user2 = create(:user)
    @two_factor_user1 = create(:user)
    @two_factor_user2 = create(:user)
    make_two_factor_credential(@two_factor_user1)
    make_two_factor_credential(@two_factor_user2)

    create :two_factor_requirement_metadata, user: @non_2fa_user1
    create :two_factor_requirement_metadata, user: @non_2fa_user2
    create :two_factor_requirement_metadata, user: @two_factor_user1
    create :two_factor_requirement_metadata, user: @two_factor_user2

    @users = [
      @non_2fa_user1,
      @non_2fa_user2,
      @two_factor_user1,
      @two_factor_user2,
    ]
  end

  def set_users_to_requirement_state(state)
    @users.each do |u|
      u.two_factor_requirement_metadata.update!(state: User.account_two_factor_requirement_states[state])
    end
  end

  context "#not_yet_notified" do
    test "returns all users" do
      set_users_to_requirement_state(:warning)
      metadatas = TwoFactorRequirementMetadata.not_yet_notified
      assert_equal 4, metadatas.count, "Expected 4 users"
      user_ids = metadatas.pluck(:user_id)
      assert_includes user_ids, @non_2fa_user1.id
      assert_includes user_ids, @non_2fa_user2.id
    end
  end

  context "#first_warning_not_sent" do
    test "returns all users" do
      Timecop.freeze do
        set_users_to_requirement_state(:warning)
        @users.each do |u|
          u.two_factor_requirement_metadata.update!(required_by: Time.now.utc + 31.days, last_email_notified_at: Time.now.utc - 1.day)
        end
        metadatas = TwoFactorRequirementMetadata.first_warning_not_sent
        assert_equal 4, metadatas.count, "Expected 4 users"
        user_ids = metadatas.pluck(:user_id)
        assert_includes user_ids, @non_2fa_user1.id
        assert_includes user_ids, @non_2fa_user2.id
      end
    end

    test "return all users with null last_email_notified_at" do
      Timecop.freeze do
        set_users_to_requirement_state(:warning)
        @users.each do |u|
          u.two_factor_requirement_metadata.update!(required_by: Time.now.utc + 31.days, last_email_notified_at: nil)
        end
        metadatas = TwoFactorRequirementMetadata.first_warning_not_sent
        assert_equal 4, metadatas.count, "Expected 4 users"
        user_ids = metadatas.pluck(:user_id)
        assert_includes user_ids, @non_2fa_user1.id
        assert_includes user_ids, @non_2fa_user2.id
      end
    end
  end

  context "#second_warning_not_sent" do
    test "returns all users" do
      Timecop.freeze do
        set_users_to_requirement_state(:warning)
        @users.each do |u|
          u.two_factor_requirement_metadata.update!(required_by: Time.now.utc + 3.weeks, last_email_notified_at: Time.now.utc - 1.day)
        end
        metadatas = TwoFactorRequirementMetadata.second_warning_not_sent
        assert_equal 4, metadatas.count, "Expected 4 users"
        user_ids = metadatas.pluck(:user_id)
        assert_includes user_ids, @non_2fa_user1.id
        assert_includes user_ids, @non_2fa_user2.id
      end
    end

    test "returns all users with null last_email_notified_at" do
      Timecop.freeze do
        set_users_to_requirement_state(:warning)
        @users.each do |u|
          u.two_factor_requirement_metadata.update!(required_by: Time.now.utc + 3.weeks, last_email_notified_at: nil)
        end
        metadatas = TwoFactorRequirementMetadata.second_warning_not_sent
        assert_equal 4, metadatas.count, "Expected 4 users"
        user_ids = metadatas.pluck(:user_id)
        assert_includes user_ids, @non_2fa_user1.id
        assert_includes user_ids, @non_2fa_user2.id
      end
    end
  end

  context "#third_warning_not_sent" do
    test "returns all users" do
      Timecop.freeze do
        set_users_to_requirement_state(:warning)
        @users.each do |u|
          u.two_factor_requirement_metadata.update!(required_by: Time.now.utc + 1.week, last_email_notified_at: Time.now.utc - 1.day)
        end
        metadatas = TwoFactorRequirementMetadata.third_warning_not_sent
        assert_equal 4, metadatas.count, "Expected 4 users"
        user_ids = metadatas.pluck(:user_id)
        assert_includes user_ids, @non_2fa_user1.id
        assert_includes user_ids, @non_2fa_user2.id
      end
    end

    test "returns all users with null last_email_notified_at" do
      Timecop.freeze do
        set_users_to_requirement_state(:warning)
        @users.each do |u|
          u.two_factor_requirement_metadata.update!(required_by: Time.now.utc + 1.week, last_email_notified_at: nil)
        end
        metadatas = TwoFactorRequirementMetadata.third_warning_not_sent
        assert_equal 4, metadatas.count, "Expected 4 users"
        user_ids = metadatas.pluck(:user_id)
        assert_includes user_ids, @non_2fa_user1.id
        assert_includes user_ids, @non_2fa_user2.id
      end
    end
  end

  context "#final_warning_not_sent" do
    test "returns all users" do
      Timecop.freeze do
        set_users_to_requirement_state(:warning)
        @users.each do |u|
          u.two_factor_requirement_metadata.update!(required_by: Time.now.utc + 1.day, last_email_notified_at: Time.now.utc - 1.day)
        end
        metadatas = TwoFactorRequirementMetadata.final_warning_not_sent
        assert_equal 4, metadatas.count, "Expected 4 users"
        user_ids = metadatas.pluck(:user_id)
        assert_includes user_ids, @non_2fa_user1.id
        assert_includes user_ids, @non_2fa_user2.id
      end
    end

    test "returns all users with null last_email_notified_at" do
      Timecop.freeze do
        set_users_to_requirement_state(:warning)
        @users.each do |u|
          u.two_factor_requirement_metadata.update!(required_by: Time.now.utc + 1.day, last_email_notified_at: nil)
        end
        metadatas = TwoFactorRequirementMetadata.final_warning_not_sent
        assert_equal 4, metadatas.count, "Expected 4 users"
        user_ids = metadatas.pluck(:user_id)
        assert_includes user_ids, @non_2fa_user1.id
        assert_includes user_ids, @non_2fa_user2.id
      end
    end
  end

  context "#final_notification_not_sent" do
    test "returns all users" do
      set_users_to_requirement_state(:required)
      metadatas = TwoFactorRequirementMetadata.final_notification_not_sent
      assert_equal 4, metadatas.count, "Expected 4 users"
      user_ids = metadatas.pluck(:user_id)
      assert_includes user_ids, @non_2fa_user1.id
      assert_includes user_ids, @non_2fa_user2.id
    end
  end
end
