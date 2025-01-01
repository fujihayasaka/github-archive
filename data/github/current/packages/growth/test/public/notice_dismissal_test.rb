# typed: false
# frozen_string_literal: true
require "test_helper"

class Growth::NoticeDismissalTest < GitHub::TestCase
  setup do
    user = create(:user)
    GitHub.flipper[:growth_kv].enable
    @handler = Growth::NoticeDismissal.new(user)
  end

  test "dismissed_at returns nil when notice is not dismissed" do
    assert_nil @handler.dismissed_user_notice_at("test_notice_name")
  end

  test "dismissed_at returns dismissed time for user notice" do
    Timecop.freeze do
      @handler.dismiss_user_notice("test_notice_name")
      compare_with_now(@handler.dismissed_user_notice_at("test_notice_name"))
    end
  end

  test "dismissed_at returns dismissed time for organization notice" do
    org = create(:organization)
    Timecop.freeze do
      @handler.dismiss_organization_notice("test_notice_name", organization_id: org.id)
      compare_with_now(@handler.dismissed_organization_notice_at("test_notice_name", org.id))
    end
  end

  test "dismissed_at returns dismissed time for business notice" do
    Timecop.freeze do
      @handler.dismiss_business_notice("test_notice_name", business_id: 2)
      compare_with_now(@handler.dismissed_business_notice_at("test_notice_name", business_id: 2))
    end
  end

  test "dismissed_at returns dismissed time for repository notice" do
    Timecop.freeze do
      repository_id = 1
      @handler.dismiss_repository_notice("test_notice_name", repository_id: repository_id)
      compare_with_now(@handler.dismissed_repository_notice_at("test_notice_name", repository_id: repository_id))
    end
  end

  test "dismissed_business_notice? returns false when notice is not dismissed" do
    refute @handler.dismissed_business_notice?("test_notice_name", business_id: 1)
  end

  test "dismissed_business_notice? returns true when notice is dismissed" do
    @handler.dismiss_business_notice("test_notice_name", business_id: 1)
    assert @handler.dismissed_business_notice?("test_notice_name", business_id: 1)
  end

  test "dismiss_organization_notice dismisses the organization notice" do
    org = create(:organization)
    @handler.dismiss_organization_notice("test_notice_name", organization_id: org.id)
    assert @handler.dismissed_organization_notice?("test_notice_name", organization_id: org.id)
  end

  context "with invalid notice" do
    test "throws an exception for invalid organization notices" do
      assert_raises(ArgumentError) do
        @handler.dismiss_organization_notice("invalid_notice", organization_id: 2)
      end
    end

    test "throws an exception for invalid repository notices" do
      assert_raises(ArgumentError) do
        @handler.dismiss_repository_notice("invalid_notice", repository_id: 1)
      end
    end

    test "throws an exception for invalid business notices" do
      assert_raises(ArgumentError) do
        @handler.dismiss_business_notice("invalid_notice", business_id: 1)
      end
    end

    test "throws an exception for invalid user notices" do
      assert_raises(ArgumentError) do
        @handler.dismiss_user_notice("invalid_notice")
      end
    end
  end

  test "dismiss_repository_notice dismisses the repository notice" do
    @handler.dismiss_repository_notice("test_notice_name", repository_id: 1)
    assert @handler.dismissed_repository_notice?("test_notice_name", repository_id: 1)
  end

  test "dismissed_organization_notice? returns false when notice is not dismissed" do
    org = create(:organization)
    refute @handler.dismissed_organization_notice?("test_notice_name", organization_id: org.id)
  end

  test "dismissed_organization_notice? returns true when notice is dismissed" do
    org = create(:organization)
    @handler.dismiss_organization_notice("test_notice_name", organization_id: org.id)
    assert @handler.dismissed_organization_notice?("test_notice_name", organization_id: org.id)
  end

  test "dismissed_repository_notice? returns false when notice is not dismissed" do
    refute @handler.dismissed_repository_notice?("test_notice_name", repository_id: 1)
  end

  test "dismissed_repository_notice? returns true when notice is dismissed" do
    @handler.dismiss_repository_notice("test_notice_name", repository_id: 1)
    assert @handler.dismissed_repository_notice?("test_notice_name", repository_id: 1)
  end

  test "reset_user_notice resets the user notice" do
    notice = "test_notice_name"
    @handler.dismiss_user_notice(notice)
    @handler.reset_user_notice(notice)
    refute @handler.dismissed_user_notice?(notice)
  end

  test "reset_business_notice resets the business notice" do
    notice = "test_notice_name"
    business_id = 1
    @handler.dismiss_business_notice(notice, business_id: business_id)
    @handler.reset_business_notice(notice, business_id: business_id)
    refute @handler.dismissed_business_notice?(notice, business_id: business_id)
  end

  test "reset_organization_notice resets the organization notice" do
    notice = "test_notice_name"
    org_id = 1
    @handler.dismiss_organization_notice(notice, organization_id: org_id)
    @handler.reset_organization_notice(notice, organization_id: org_id)
    refute @handler.dismissed_organization_notice?(notice, organization_id: org_id)
  end

  test "reset_repository_notice resets the repository notice" do
    notice = "test_notice_name"
    repository_id = 1
    @handler.dismiss_repository_notice(notice, repository_id: repository_id)
    @handler.reset_repository_notice(notice, repository_id: repository_id)
    refute @handler.dismissed_repository_notice?(notice, repository_id: repository_id)
  end

  test "dismiss_organization_notice sets expiration time when provided" do
    expires = 1.hour.from_now
    @handler.dismiss_organization_notice("test_notice_name", organization_id: 1, expires: expires)
    travel_to(expires + 1.minute) do
      refute @handler.dismissed_organization_notice?("test_notice_name", organization_id: 1)
    end
  end

  test "dismiss_business_notice sets expiration time when provided" do
    expires = 1.hour.from_now
    @handler.dismiss_business_notice("test_notice_name", business_id: 1, expires: expires)
    travel_to(expires + 1.minute) do
      refute @handler.dismissed_business_notice?("test_notice_name", business_id: 1)
    end
  end

  test "dismiss_repository_notice sets expiration time when provided" do
    expires = 1.hour.from_now
    @handler.dismiss_repository_notice("test_notice_name", repository_id: 1, expires: expires)
    travel_to(expires + 1.minute) do
      refute @handler.dismissed_repository_notice?("test_notice_name", repository_id: 1)
    end
  end

  test "dismiss_user_notice sets expiration time when provided" do
    expires = Time.new(2023, 4, 20, 12, 0, 0)
    @handler.dismiss_user_notice("test_notice_name", expires: expires)

    travel_to(expires - 1.minute) do
      assert @handler.dismissed_user_notice?("test_notice_name")
    end

    travel_to(expires + 1.minute) do
      refute @handler.dismissed_user_notice?("test_notice_name")
    end
  end

  def compare_with_now(time)
    assert_equal Time.now.utc.strftime("%Y-%m-%d %H:%M:%S"), time.strftime("%Y-%m-%d %H:%M:%S")
  end
end
