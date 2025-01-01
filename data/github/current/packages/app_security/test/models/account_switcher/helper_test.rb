# typed: true
# frozen_string_literal: true

require "test_helper"

class AccountSwitcherTest < GitHub::TestCase
  include DogstatsTestHelpers

  setup do
    @user1 = create(:user)
    @user2 = create(:user)
    @user3 = create(:user)
    @user1_session = create(:user_session, user: @user1)
    @user2_session = create(:user_session, user: @user2)
  end

  context "#enabled?" do
    test "returns false when both params are nil" do
      refute AccountSwitcher::Helper.new(nil, nil).enabled?
    end

    test "returns true when nil saved session hash" do
      assert AccountSwitcher::Helper.new(@user1, nil).enabled?
    end
  end

  context "#can_add_account?" do
    test "returns false if there is no user" do
      AccountSwitcher::Helper.any_instance.expects(:enabled?).never
      refute AccountSwitcher::Helper.new(nil, {}).can_add_account?
    end

    test "returns false if there is a user and is not enabled?" do
      AccountSwitcher::Helper.any_instance.expects(:enabled?).once.returns(false)
      refute AccountSwitcher::Helper.new(@user1, {}).can_add_account?
    end

    test "returns true if there is a user and is enabled?" do
      AccountSwitcher::Helper.any_instance.expects(:enabled?).at_least_once.returns(true)
      assert AccountSwitcher::Helper.new(@user1, {}).can_add_account?
    end

    test "returns false if there is a user and is enabled? but has reached max accounts" do
      AccountSwitcher::Helper.any_instance.expects(:enabled?).at_least_once.returns(true)
      AccountSwitcher::Helper.any_instance.expects(:at_account_maximum?).once.returns(true)
      refute AccountSwitcher::Helper.new(@user1, {}).can_add_account?
    end
  end

  context "#account_already_exists?" do
    test "returns false if no user_id is provided" do
      AccountSwitcher::Helper.any_instance.expects(:enabled?).never
      AccountSwitcher::Helper.any_instance.expects(:stashed_accounts).never
      refute AccountSwitcher::Helper.new(nil, {}).account_already_exists?(nil)
    end

    test "returns false if not enabled" do
      AccountSwitcher::Helper.any_instance.expects(:enabled?).once.returns(false)
      AccountSwitcher::Helper.any_instance.expects(:stashed_accounts).never
      refute AccountSwitcher::Helper.new(nil, {}).account_already_exists?(@user1.id)
    end

    test "returns false if no stashed accounts" do
      AccountSwitcher::Helper.any_instance.expects(:enabled?).once.returns(true)
      AccountSwitcher::Helper.any_instance.expects(:stashed_accounts).once.returns(
        AccountSwitcher::StashedAccounts.new(
          valid: [],
          invalid: []
        )
      )
      refute AccountSwitcher::Helper.new(nil, {}).account_already_exists?(@user1.id)
    end

    test "returns false if provided user_id does not belong to any stashed accounts" do
      AccountSwitcher::Helper.any_instance.expects(:enabled?).once.returns(true)
      AccountSwitcher::Helper.any_instance.expects(:stashed_accounts).once.returns(
        AccountSwitcher::StashedAccounts.new(
          valid: [
            AccountSwitcher::StashedAccount.new(user: @user2, user_session_key: "key", user_session: @user2_session, valid: true),
          ],
          invalid: []
        )
      )
      refute AccountSwitcher::Helper.new(nil, {}).account_already_exists?(@user1.id)
    end

    test "returns true if provided user_id belongs to a stashed account" do
      AccountSwitcher::Helper.any_instance.expects(:enabled?).once.returns(true)
      AccountSwitcher::Helper.any_instance.expects(:stashed_accounts).once.returns(
        AccountSwitcher::StashedAccounts.new(
          valid: [
            AccountSwitcher::StashedAccount.new(user: @user1, user_session_key: "key1", user_session: @user1_session, valid: true),
            AccountSwitcher::StashedAccount.new(user: @user2, user_session_key: "key2", user_session: @user2_session, valid: true),
          ],
          invalid: []
        )
      )
      assert AccountSwitcher::Helper.new(nil, {}).account_already_exists?(@user1.id)
    end
  end

  context "#invalid_account_already_exists?" do
    test "returns false if no display_login is provided" do
      AccountSwitcher::Helper.any_instance.expects(:enabled?).never
      AccountSwitcher::Helper.any_instance.expects(:stashed_accounts).never
      refute AccountSwitcher::Helper.new(nil, {}).invalid_account_already_exists?(nil)
    end

    test "returns false if not enabled" do
      AccountSwitcher::Helper.any_instance.expects(:enabled?).once.returns(false)
      AccountSwitcher::Helper.any_instance.expects(:stashed_accounts).never
      refute AccountSwitcher::Helper.new(nil, {}).invalid_account_already_exists?(@user1.display_login)
    end

    test "returns false if no stashed accounts" do
      AccountSwitcher::Helper.any_instance.expects(:enabled?).once.returns(true)
      AccountSwitcher::Helper.any_instance.expects(:stashed_accounts).once.returns(
        AccountSwitcher::StashedAccounts.new(
          valid: [],
          invalid: []
        )
      )
      refute AccountSwitcher::Helper.new(nil, {}).invalid_account_already_exists?(@user1.display_login)
    end

    test "returns false if at account limit but the given account is still stashed and valid" do
      AccountSwitcher::Helper.stub_const(:SAVED_ACCOUNTS_LIMIT, 2) do
        AccountSwitcher::Helper.any_instance.expects(:enabled?).once.returns(true)
        AccountSwitcher::Helper.any_instance.expects(:stashed_accounts).once.returns(
          AccountSwitcher::StashedAccounts.new(
            valid: [
              AccountSwitcher::StashedAccount.new(user: @user1, user_session_key: "key1", user_session: @user1_session, valid: true),
              AccountSwitcher::StashedAccount.new(user: @user2, user_session_key: "key2", user_session: @user2_session, valid: true),
            ],
            invalid: [
              AccountSwitcher::StashedAccount.new(user: @user3, user_session_key: "key3", user_session: @user3_session, valid: false),
            ]
          )
        )
        refute AccountSwitcher::Helper.new(@user1, {}).invalid_account_already_exists?(@user2.display_login)
      end
    end

    test "returns true if at account limit but the given account is still stashed and invalid" do
      AccountSwitcher::Helper.stub_const(:SAVED_ACCOUNTS_LIMIT, 2) do
        AccountSwitcher::Helper.any_instance.expects(:enabled?).once.returns(true)
        AccountSwitcher::Helper.any_instance.expects(:stashed_accounts).once.returns(
          AccountSwitcher::StashedAccounts.new(
            valid: [
              AccountSwitcher::StashedAccount.new(user: @user1, user_session_key: "key1", user_session: @user1_session, valid: true),
            ],
            invalid: [
              AccountSwitcher::StashedAccount.new(user: @user2, user_session_key: "key2", user_session: @user2_session, valid: true),
              AccountSwitcher::StashedAccount.new(user: @user3, user_session_key: "key3", user_session: @user3_session, valid: false),
            ]
          )
        )
        assert AccountSwitcher::Helper.new(@user1, {}).invalid_account_already_exists?(@user2.display_login)
      end
    end
  end

  context "#stashed_accounts" do
    test "is memoized" do
      AccountSwitcher::Helper.any_instance.expects(:enabled?).once.returns(false)
      switcher_lib = AccountSwitcher::Helper.new(@user, {})
      switcher_lib.stashed_accounts
      AccountSwitcher::Helper.any_instance.expects(:enabled?).never
      switcher_lib.stashed_accounts
    end

    test "returns empty valid and invalid accounts if not enabled?" do
      AccountSwitcher::Helper.any_instance.expects(:enabled?).once.returns(false)
      result = AccountSwitcher::Helper.new(@user, {}).stashed_accounts
      expected_result = AccountSwitcher::StashedAccounts.new(valid: [], invalid: [])
      assert_equal(expected_result.valid, result.valid)
      assert_equal(expected_result.invalid, result.invalid)
    end

    test "returns empty valid and invalid accounts if saved session hash has no values" do
      AccountSwitcher::Helper.any_instance.expects(:enabled?).once.returns(true)
      result = AccountSwitcher::Helper.new(@user, {}).stashed_accounts
      expected_result = AccountSwitcher::StashedAccounts.new(valid: [], invalid: [])
      assert_equal(expected_result.valid, result.valid)
      assert_equal(expected_result.invalid, result.invalid)
    end

    test "returns expected accounts that do not belong to the passed in user" do
      # test a user ID that doesn't belong to a User record
      deleted_user = create(:user)
      deleted_user_id = deleted_user.id
      deleted_user.destroy!

      AccountSwitcher::Helper.any_instance.expects(:enabled?).once.returns(true)
      UserSession.expects(:authenticate).with("sessionKey1").returns([@user1_session, "sessionKey1"])
      UserSession.expects(:authenticate).with("sessionKey3").returns(nil) # mimics a key that doesn't belong to an authenticated session

      saved_user_session_hash = {
        deleted_user_id => "sessionKey0",
        @user1.id => "sessionKey1",
        @user2.id => "sessionKey2",
        @user3.id => "sessionKey3"
      }
      result = AccountSwitcher::Helper.new(@user2, saved_user_session_hash).stashed_accounts
      expected_result = AccountSwitcher::StashedAccounts.new(
        valid: [
          AccountSwitcher::StashedAccount.new(user: @user1, user_session_key: "sessionKey1", user_session: @user1_session, valid: true),
          # user2_session isn't included since it belongs to the user that is passed in
        ],
        invalid: [
          AccountSwitcher::StashedAccount.new(user: @user3, user_session_key: "sessionKey3", user_session: @user3_session, valid: false),
        ]
      )
      assert_equal(expected_result.valid.size, result.valid.size)
      assert_equal(expected_result.invalid.size, result.invalid.size)
      assert expected_result.valid.all? { |account| result.valid.include?(account) }
      assert expected_result.invalid.all? { |account| result.invalid.include?(account) }
    end

    test "returns expected hash when nil user is provided" do
      # test a user ID that doesn't belong to a User record
      deleted_user = create(:user)
      deleted_user_id = deleted_user.id
      deleted_user.destroy!

      AccountSwitcher::Helper.any_instance.expects(:enabled?).once.returns(true)
      UserSession.expects(:authenticate).with("sessionKey1").returns([@user1_session, "sessionKey1"])
      UserSession.expects(:authenticate).with("sessionKey2").returns([@user2_session, "sessionKey2"])
      UserSession.expects(:authenticate).with("sessionKey3").returns(nil) # mimics a key that doesn't belong to an authenticated session

      saved_user_session_hash = {
        deleted_user_id => "sessionKey0",
        @user1.id => "sessionKey1",
        @user2.id => "sessionKey2",
        @user3.id => "sessionKey3"
      }
      result = AccountSwitcher::Helper.new(nil, saved_user_session_hash).stashed_accounts
      expected_result = AccountSwitcher::StashedAccounts.new(
        valid: [
          AccountSwitcher::StashedAccount.new(user: @user1, user_session_key: "sessionKey1", user_session: @user1_session, valid: true),
          AccountSwitcher::StashedAccount.new(user: @user2, user_session_key: "sessionKey2", user_session: @user2_session, valid: true),
        ],
        invalid: [
          AccountSwitcher::StashedAccount.new(user: @user3, user_session_key: "sessionKey3", user_session: @user3_session, valid: false),
        ]
      )
      assert_equal(expected_result.valid.size, result.valid.size)
      assert_equal(expected_result.invalid.size, result.invalid.size)
      assert expected_result.valid.all? { |account| result.valid.include?(account) }
      assert expected_result.invalid.all? { |account| result.invalid.include?(account) }
    end

    test "ignores entries where session and user_id mismatch" do
      AccountSwitcher::Helper.any_instance.expects(:enabled?).once.returns(true)
      UserSession.expects(:authenticate).with("sessionKey1").returns([@user1_session, "sessionKey1"])
      UserSession.expects(:authenticate).with("sessionKey2").returns([@user2_session, "sessionKey2"])

      saved_user_session_hash = {
        @user1.id => "sessionKey1",
        @user3.id => "sessionKey2",  # mismatch between user and session
      }
      result = AccountSwitcher::Helper.new(nil, saved_user_session_hash).stashed_accounts
      expected_result = AccountSwitcher::StashedAccounts.new(
        valid: [
          AccountSwitcher::StashedAccount.new(user: @user1, user_session_key: "sessionKey1", user_session: @user1_session, valid: true),
        ],
        invalid: [],
      )
      assert_equal(expected_result.valid.size, result.valid.size)
      assert_equal(expected_result.invalid.size, result.invalid.size)
      assert expected_result.valid.all? { |account| result.valid.include?(account) }

      assert_dogstats_increment(1, "account_switcher.saved_session_mismatch")
    end
  end
end
