# typed: true
# frozen_string_literal: true

module SlashCommands
  class FlashTest < GitHub::TestCase
    test "can set and retrieve info, notice, and error messages" do
      flash = Flash.new
      flash.info = "some info"
      flash.notice = "some notice"
      flash.error = "some error"

      assert_equal "some info", flash.info
      assert_equal "some notice", flash.notice
      assert_equal "some error", flash.error
    end

    test "#present? returns true when any message is set" do
      flash_info = Flash.new
      flash_info.info = "some info"

      flash_notice = Flash.new
      flash_notice.notice = "some notice"

      flash_error = Flash.new
      flash_error.error = "some error"

      assert flash_info.present?
      assert flash_notice.present?
      assert flash_error.present?
      refute Flash.new.present?
    end
  end
end
