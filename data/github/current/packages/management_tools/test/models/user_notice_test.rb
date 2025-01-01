# typed: true
# frozen_string_literal: true

require "test_helper"

class UserNoticeTest < GitHub::TestCase
  def valid_notice_seed
    {
      "effective_date" => Time.now.to_s,
      "name" => "notice_name#{Time.now}",
      "hide_from_new_user" => false,
      "area_of_responsibility" => "github/github",
    }
  end

  setup do
    UserNotice.load_notices(Rails.root.join("test", "fixtures", "notices.yml"))
  end

  teardown do
    UserNotice.load_notices
  end

  context "config/notices.yml" do
    test "has all required fields" do
      file_path = Rails.root.join("config", "notices.yml")
      notices_file = YAML.safe_load(File.read(file_path))
      errors = []

      valid_services = nil
      errors = notices_file["notices"].map do |notice|
        next if notice["decommission_date"]

        reasons = []
        reasons << "Missing name" unless notice["name"]
        reasons << "Missing effective_date" unless notice["effective_date"]
        reasons << "Missing hide_from_new_user" if notice["hide_from_new_user"].nil?

        unless GitHub.enterprise?
          catalog_service = notice["catalog_service"]
          reasons << "Missing catalog_service" if catalog_service.blank?
        end

        next if reasons.empty?

        "#{reasons.join(", ")} in #{notice}"
      end.compact

      assert errors.empty?,
        "#{errors.count} notice definitions from `/config/notices.yml` have errors: \n#{errors.join("\n")}"
    end
  end

  context ".all" do
    test "has all notices" do
      file_path = (Rails.root.join("test", "fixtures", "notices.yml"))
      notice_definitions = YAML.safe_load(File.read(file_path))
      UserNotice.load_notices(file_path)

      assert_equal notice_definitions["notices"].count, UserNotice.all.count
    end
  end

  context ".find" do
    test "returns a defined notice" do
      assert_equal "always_active", UserNotice.find("always_active").name
    end

    test "returns a decommissioned notice" do
      assert_equal "past_decommission", UserNotice.find("past_decommission").name
    end

    test "returns nil when a notice is not defined" do
      assert_nil GitHub::Plan.find("invalid_notice")
    end
  end

  context ".new" do
    test "initializes without raising" do
      UserNotice.new(valid_notice_seed)
    end

    test "requires a name" do
      assert_raises { UserNotice.new(valid_notice_seed.without("name")) }
    end

    test "requires an effective_date" do
      assert_raises { UserNotice.new(valid_notice_seed.without("effective_date")) }
    end

    test "requires hide_from_new_user" do
      assert_raises { UserNotice.new(valid_notice_seed.without("hide_from_new_user")) }
    end
  end

  context "#decommissioned?" do
    test "returns false for nil decommission_date" do
      notice = UserNotice.new(valid_notice_seed)

      refute notice.decommissioned?
    end

    test "returns false when decommission_date is in the futute" do
      notice = UserNotice.new(valid_notice_seed.merge("decommission_date" => 1.year.from_now.to_s))

      refute notice.decommissioned?
    end

    test "returns true when decommission_date is in the past" do
      notice = UserNotice.new(valid_notice_seed.merge("decommission_date" => 1.year.ago.to_s))

      assert notice.decommissioned?
    end
  end

  context "#effective_at" do
    test "returns nil when there is no effective date" do
      notice = UserNotice.find("no_effective_date")
      assert_nil notice.effective_at
    end

    test "returns DateTime representation of the effective date" do
      notice = UserNotice.find("always_active")
      assert_equal "2019-01-01", notice.effective_date

      result = notice.effective_at

      assert_instance_of DateTime, result
      assert_equal DateTime.parse("2019-01-01"), result
    end
  end

  context "#effective?" do
    test "returns true for current effective_date and nil decommission_date" do
      notice = UserNotice.new(valid_notice_seed)

      assert notice.effective?
    end

    test "returns true for current effective_date and future decommission_date" do
      notice = UserNotice.new(valid_notice_seed.merge("decommission_date" => 1.year.from_now.to_s))

      assert notice.effective?
    end

    test "returns false when effective_date is in the future" do
      notice = UserNotice.new(valid_notice_seed.merge("effective_date" => 1.year.from_now.to_s))

      refute notice.effective?
    end

    test "returns false when decommission_date is in the past" do
      notice = UserNotice.new(valid_notice_seed.merge("decommission_date" => 1.year.ago.to_s))

      refute notice.effective?
    end

    test "returns false when effective_date is blank" do
      notice = UserNotice.find("no_effective_date")
      refute_predicate notice, :effective?
    end
  end
end
