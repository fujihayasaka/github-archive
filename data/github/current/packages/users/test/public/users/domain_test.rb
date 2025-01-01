# typed: true
# frozen_string_literal: true

require "test_helper"

class Users::DomainTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @pull = create(:pull_request, :disable_disk_access)
  end

  def setup
    @accessor = Users::Domain.new
  end

  context "#by_id" do
    test "loads the user for the given id" do
      user = create(:user)
      result = @accessor.by_id(user.id)

      assert_equal user, result
    end

    test "executes no queries for invalid ids" do
      assert_query_count(0) { @accessor.by_id(0) }
    end
  end

  context "#by_login" do
    test "loads the user for the given login" do
      user = create(:user)
      result = @accessor.by_login(user.login)

      assert_equal user, result
    end

    test "executes no queries for invalid logins" do
      assert_query_count(0) { @accessor.by_login("") }
    end
  end
end
