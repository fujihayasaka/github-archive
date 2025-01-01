# typed: true
# frozen_string_literal: true

require "test_helper"

class DashboardNoticesStoreTest < GitHub::TestCase
  setup do
    # set up a user with no notice
    @no_notice_user = create(:user)
    ensure_no_notices_for_user(@no_notice_user.id)

    # set up a user with a single notice
    @one_notice_user = create(:user)
    DashboardNoticesStore.add(@one_notice_user.id, :example_notice_name)

    # set up user with deactivated notice
    @deactivated_notice_user = create(:user)
    DashboardNoticesStore.add(@deactivated_notice_user.id, :example_notice_name)
    DashboardNoticesStore.deactivate(@deactivated_notice_user.id, :example_notice_name)

    # set up user with multiple notices
    @multiple_notice_user = create(:user)
    DashboardNoticesStore.add(@multiple_notice_user.id, :orgs_newbie)
    DashboardNoticesStore.add(@multiple_notice_user.id, :coupon_will_expire)
  end

  context "add" do
    test "can add a notice" do
      result = DashboardNoticesStore.add(@no_notice_user.id, :example_notice_name)

      assert_equal true, result.ok?
      assert_equal true, result.value!
      notices = get_notices_for_user_id(@no_notice_user.id)
      assert_equal 1, notices.length
    end

    test "can not add a notice twice" do
      DashboardNoticesStore.add(@no_notice_user.id, :example_notice_name)
      DashboardNoticesStore.add(@no_notice_user.id, :example_notice_name)

      notices = get_notices_for_user_id(@no_notice_user.id)
      assert_equal 1, notices.length
    end

    test "adding a notice for user defaults to active" do
      DashboardNoticesStore.add(@no_notice_user.id, :example_notice_name)

      notice = get_notice(@no_notice_user.id, :example_notice_name)
      assert_equal @no_notice_user.id, notice[:user_id]
      assert_equal "example_notice_name", notice[:notice_name]
      assert_equal 1, notice[:active]
    end

    test "add notice after it's deactivation does not reactivate notice" do
      DashboardNoticesStore.add(@no_notice_user.id, :example_notice_name)
      DashboardNoticesStore.deactivate(@no_notice_user.id, :example_notice_name)
      assert_notice_deactivated @no_notice_user.id, :example_notice_name

      DashboardNoticesStore.add(@no_notice_user.id, :example_notice_name)
      assert_notice_deactivated @no_notice_user.id, :example_notice_name
    end
  end

  context "add_bulk" do
    test "can add a notices using bulk method" do
      user1 = create(:user)
      ensure_no_notices_for_user(user1.id)
      user2 = create(:user)
      ensure_no_notices_for_user(user2.id)

      result = DashboardNoticesStore.bulk_add([user1.id, user2.id], :example_notice_name)

      assert_equal true, result.ok?, "reslt should be ok"
      assert_equal true, result.value!, "result value should be true"
      notices = get_notices_for_user_id(user1.id)
      assert_equal 1, notices.length, "user1 should have 1 notice"
      notices = get_notices_for_user_id(user2.id)
      assert_equal 1, notices.length, "user2 should have 1 notice"
    end
  end unless GitHub.single_business_environment?

  context "delete" do
    test "can delete a notice" do
      DashboardNoticesStore.delete(@one_notice_user.id, :example_notice_name)

      notice = get_notice(@one_notice_user.id, :example_notice_name)
      assert_nil notice
    end

    test "can delete a deactivated notice" do
      DashboardNoticesStore.deactivate(@one_notice_user.id, :example_notice_name)
      result = DashboardNoticesStore.delete(@one_notice_user.id, :example_notice_name)
      assert_equal true, result.ok?
      assert_equal true, result.value!

      notice = get_notice(@one_notice_user.id, :example_notice_name)
      assert_nil notice
    end
  end

  context "delete_all_for_user" do
    test "deletes all notices for the given user" do
      result = DashboardNoticesStore.delete_all_for_user(@multiple_notice_user.id)
      assert_equal true, result.ok?
      assert_equal true, result.value!

      notices = get_notices_for_user_id(@multiple_notice_user.id)
      assert_empty notices
    end

    test "returns false result when user had no notices to delete" do
      result = DashboardNoticesStore.delete_all_for_user(@no_notice_user.id)
      assert_equal true, result.ok?
      assert_equal false, result.value!
    end
  end

  context "deactivate" do
    test "can deactivate notice" do
      result = DashboardNoticesStore.deactivate(@one_notice_user.id, :example_notice_name)
      assert_equal true, result.ok?
      assert_equal true, result.value!

      notice = get_notice(@one_notice_user.id, :example_notice_name)
      assert_equal 0, notice[:active]
    end

    test "do not deactivate notice that does not exist" do
      result = DashboardNoticesStore.deactivate(0, :example_notice_name)
      assert_equal false, result.value!
    end
  end

  context "get_for_user_id" do
    test "can get notices for user" do
      result = DashboardNoticesStore.get_for_user_id(@multiple_notice_user.id)
      assert_equal true, result.ok?
    end

    test "gets correct notices for user" do
      result = DashboardNoticesStore.get_for_user_id(@multiple_notice_user.id)
      notices = result.value!
      names = notices.map { |notice| notice.name }
      assert_same_elements %w[orgs_newbie coupon_will_expire], names
    end

    test "returns empty set for user with no notices" do
      result = DashboardNoticesStore.get_for_user_id(0) # no such user
      assert_equal true, result.ok?
      assert_equal [], result.value!
    end

    test "returns only active notices" do
      DashboardNoticesStore.deactivate(@multiple_notice_user.id, "orgs_newbie")
      result = DashboardNoticesStore.get_for_user_id(@multiple_notice_user.id)
      notices = result.value!
      assert_equal 1, notices.length
      assert_equal "coupon_will_expire", notices.first.name
    end
  end

  # Helper methods

  def assert_notice_deactivated(user_id, notice_name)
    notice = get_notice(user_id, notice_name)
    assert_equal 0, notice[:active]
  end

  def ensure_no_notices_for_user(user_id)
    notices = get_notices_for_user_id(user_id)
    assert_equal 0, notices.length
  end

  def get_notices_for_user_id(user_id)
    select_notices_bindings = {
      user_id: user_id,
    }
    select_notices = Arel.sql <<-SQL, **select_notices_bindings
      SELECT user_id, notice_name, active FROM dashboard_notices
      WHERE user_id = :user_id
    SQL

    ApplicationRecord::Domain::Users.connection.select_rows(select_notices).map { |r| { user_id: r[0], notice_name: r[1], active: r[2] } }
  end

  def get_notice(user_id, notice_name)
    select_notice_bindings = {
      user_id: user_id,
      notice_name: notice_name,
    }
    select_notice = Arel.sql <<-SQL, **select_notice_bindings
      SELECT user_id, notice_name, active FROM dashboard_notices
      WHERE user_id = :user_id AND notice_name = :notice_name
      LIMIT 1
    SQL

    ApplicationRecord::Domain::Users.connection.select_rows(select_notice)
      .map { |r| { user_id: r[0], notice_name: r[1], active: r[2] } }
      .first
  end

end
