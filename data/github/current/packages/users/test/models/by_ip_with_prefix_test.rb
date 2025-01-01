# typed: true
# frozen_string_literal: true

require "test_helper"

class ByIpWithPrefixTest < GitHub::TestCase
  fixtures do
    @user = create(:user, last_ip: "1.2.3.4")
    @prefix32_neighbor1 = create(:user, last_ip: "1.2.3.4")
    @prefix32_neighbor2 = create(:user, last_ip: "1.2.3.4")
    @prefix24_neighbor1 = create(:user, last_ip: "1.2.3.3")
    @prefix24_neighbor2 = create(:user, last_ip: "1.2.3.5")
    @not_neighbor = create(:user, last_ip: "1.2.0.0")
  end

  test ".by_ip_with_prefix returns empty user relation when passed in nil" do
    users = User.by_ip_with_prefix(nil, prefix: 24)
    assert_equal 0, users.size
    users = User.by_ip_with_prefix(nil, prefix: 32)
    assert_equal 0, users.size
    users = User.by_ip_with_prefix(nil)
    assert_equal 0, users.size
  end
  test ".by_ip_with_prefix defaults to prefix: 32" do
    users = User.by_ip_with_prefix("1.2.3.4")
    assert_equal 3, users.size
    assert_includes users, @user
    assert_includes users, @prefix32_neighbor1
    assert_includes users, @prefix32_neighbor2
    refute_includes users, @prefix24_neighbor1
    refute_includes users, @prefix24_neighbor2
    refute_includes users, @not_neighbor
  end

  test ".by_ip_with_prefix prefix: 32" do
    users = User.by_ip_with_prefix("1.2.3.4", prefix: 32)
    assert_equal 3, users.size
    assert_includes users, @user
    assert_includes users, @prefix32_neighbor1
    assert_includes users, @prefix32_neighbor2
    refute_includes users, @prefix24_neighbor1
    refute_includes users, @prefix24_neighbor2
    refute_includes users, @not_neighbor
  end

  test ".by_ip_with_prefix prefix: 24" do
    users = User.by_ip_with_prefix("1.2.3.4", prefix: 24)
    assert_equal 5, users.size
    assert_includes users, @user
    assert_includes users, @prefix32_neighbor1
    assert_includes users, @prefix32_neighbor2
    assert_includes users, @prefix24_neighbor1
    assert_includes users, @prefix24_neighbor2
    refute_includes users, @not_neighbor
  end
end
