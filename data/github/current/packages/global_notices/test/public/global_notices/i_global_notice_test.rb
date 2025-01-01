# typed: true
# frozen_string_literal: true

require "test_helper"

module GlobalNotices
  class IGlobalNoticeTest < GitHub::TestCase

    fixtures do
      @user = create(:user)
    end

    sig { returns(User) }
    attr_reader :user

    test "#type matches that specified" do
      assert_equal "info", GlobalNotices.domain.set(user: @user, name: :open_source_survey_2024).type
    end

    test "#snooze_interval matches that specified" do
      notice = GlobalNotices.domain.set(user: @user, name: :year_old_recovery_codes)
      assert_equal 3.months, notice.snooze_interval
    end

    test "#display? returns true if the notice is applicable", skip_enterprise: true do
      create(:organization, admin: @user, spammy: true)

      notice = GlobalNotices.domain.set(user: @user, name: :spammy_orgs)
      assert notice.display?(@user)
    end
  end
end
