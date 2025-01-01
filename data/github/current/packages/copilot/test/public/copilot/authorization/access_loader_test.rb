# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::Authorization::AccessLoaderTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  fixtures do
    @user         = create(:user)
    @copilot_user = Copilot::User.new(@user).freeze
  end

  context "#allowed?" do
    test ":NOT_EVALUATED" do
      access = Copilot::Authorization::AccessLoader.new(@copilot_user, :NOT_EVALUATED, true)
      refute access.allowed?
    end

    test "BLOCKED_ACCESS_TYPES" do
      Copilot::Authorization::AccessLoader::BLOCKED_ACCESS_TYPES.each do |access_type|
        access = Copilot::Authorization::AccessLoader.new(@copilot_user, access_type, true)
        refute access.allowed?
      end
    end

    test "!@include_snippy" do
      access = Copilot::Authorization::AccessLoader.new(@copilot_user, :FREE_EDUCATIONAL, false)
      assert access.allowed?
    end

    test "snippy check - not configured" do
      Copilot::User.any_instance.expects(:public_code_suggestions_configured?).returns(false)
      # we need to be able to modify this
      access = Copilot::Authorization::AccessLoader.new(Copilot::User.new(@user), :FREE_EDUCATIONAL, true)
      refute access.allowed?
      assert_equal :SNIPPY_NOT_CONFIGURED, access.type
    end

    test "snippy check - configured" do
      Copilot::User.any_instance.expects(:public_code_suggestions_configured?).returns(true)
      # we need to be able to modify this
      access = Copilot::Authorization::AccessLoader.new(Copilot::User.new(@user), :FREE_EDUCATIONAL, true)
      assert access.allowed?
      assert_equal :FREE_EDUCATIONAL, access.type
    end

    test "limited user - snippy configured - no quota remaining" do
      Copilot::User.any_instance.expects(:public_code_suggestions_configured?).returns(true)
      create(:copilot_limited_user, user: @user, subscribed_at: Time.now)

      Copilot::User.any_instance.expects(:has_completions_quota_remaining?).returns(false)
      Copilot::User.any_instance.expects(:has_chat_quota_remaining?).returns(false)
      access = Copilot::Authorization::AccessLoader.new(Copilot::User.new(@user), :FREE_LIMITED_COPILOT, true)
      assert access.allowed?
      assert_equal :FREE_LIMITED_COPILOT, access.type
    end
  end

  context "#verbose_reason" do
    test "snippy check - not configured" do
      Copilot::User.any_instance.expects(:public_code_suggestions_configured?).returns(false)
      # we need to be able to modify this
      access = Copilot::Authorization::AccessLoader.new(Copilot::User.new(@user), :FREE_EDUCATIONAL, true)
      refute access.allowed?
      assert_equal :SNIPPY_NOT_CONFIGURED, access.type
      assert_equal "Snippy Unconfigured", access.verbose_reason
    end

    Copilot::Authorization::AccessLoader::VERBOSE_REASONS.each do |type, reason|
      test type.to_s do
        access = Copilot::Authorization::AccessLoader.new(@copilot_user, type.upcase.to_sym, false)
        assert_equal reason, access.verbose_reason
      end
    end
  end

  context "verbose_reasons" do
    Copilot::Authorization::AccessLoader::ALL_TYPES.each do |type|
      test "verbose_reasons - #{type}" do
        assert Copilot::Authorization::AccessLoader::VERBOSE_REASONS.key?(type.to_s.downcase)
      end
    end
  end

  context "#has_cfb/cfi_access?" do
    Copilot::Authorization::AccessLoader::VERBOSE_REASONS.each do |type, _|
      test type.to_s do
        new_type = type.upcase.to_sym
        access = Copilot::Authorization::AccessLoader.new(@copilot_user, type.upcase.to_sym, false)

        if Copilot::Authorization::AccessLoader::BLOCKED_ACCESS_TYPES.include?(new_type)
          refute access.has_cfb_access?, "expected #{new_type} to not have cfb access"
          refute access.has_cfe_access?, "expected #{new_type} to not have cfe access"
          refute access.has_cfi_access?, "expected #{new_type} to not have cfi access"
          refute access.has_cfi_pro_plus_access?, "expected #{new_type} to not have cfi pro plus access"
        elsif Copilot::Authorization::AccessLoader::CFB_ACCESS_TYPES.include?(new_type)
          assert access.has_cfb_access?, "expected #{new_type} to have cfb access"
          refute access.has_cfe_access?, "expected #{new_type} to not have cfe access"
          refute access.has_cfi_access?, "expected #{new_type} to not have cfi access"
          refute access.has_cfi_pro_plus_access?, "expected #{new_type} to not have cfi pro plus access"
        elsif Copilot::Authorization::AccessLoader::CFE_ACCESS_TYPES.include?(new_type)
          assert access.has_cfb_access?, "expected #{new_type} to have cfb access"
          assert access.has_cfe_access?, "expected #{new_type} to have cfe access"
          refute access.has_cfi_access?, "expected #{new_type} to not have cfi access"
          refute access.has_cfi_pro_plus_access?, "expected #{new_type} to not have cfi pro plus access"
        elsif Copilot::Authorization::AccessLoader::CFI_PRO_PLUS_ACCESS_TYPES.include?(new_type)
          refute access.has_cfb_access?, "expected #{new_type} to not have cfb access"
          refute access.has_cfe_access?, "expected #{new_type} to not have cfe access"
          assert access.has_cfi_access?, "expected #{new_type} to have cfi access"
          assert access.has_cfi_pro_plus_access?, "expected #{new_type} to have cfi pro plus access"
        else
          refute access.has_cfb_access?, "expected #{new_type} to not have cfb access"
          refute access.has_cfe_access?, "expected #{new_type} to not have cfe access"
          assert access.has_cfi_access?, "expected #{new_type} to have cfi access"
          refute access.has_cfi_pro_plus_access?, "expected #{new_type} to not have cfi pro plus access"
        end
      end
    end
  end
end if GitHub.copilot_enabled?
