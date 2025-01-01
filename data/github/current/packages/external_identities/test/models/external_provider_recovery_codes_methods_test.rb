# typed: true
# frozen_string_literal: true

require "test_helper"

class ExternalProviderRecoveryCodesMethodsTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers

  fixtures do
    @org_provider = create :organization_saml_provider
    @business_provider = create :business_saml_provider
    @business = @business_provider.business || GitHub.global_business

    unless GitHub.single_business_environment?
      @emu_business = create(:business, :enterprise_managed)
      @oidc_provider = create :business_oidc_provider, business: @emu_business
    end
  end

  context "org SAML provider recovery codes" do
    test "generates recovery codes on creation" do
      refute_nil @org_provider.secret
      refute_nil @org_provider.recovery_secret
      refute_nil @org_provider.recovery_used_bitfield
      refute_predicate @org_provider, :recovery_codes_viewed?
    end

    test "unused recovery codes can be verified" do
      code = @org_provider.recovery_code(0)
      refute @org_provider.recovery_code_used?(0)

      assert_equal true, @org_provider.verify_recovery_code!(code), "Recovery code '#{code}' should be valid"
      assert @org_provider.recovery_code_used?(0)
    end

    test "used recovery codes cannot be verified" do
      code = @org_provider.recovery_code(0)
      refute @org_provider.recovery_code_used?(0)

      assert_equal true, @org_provider.verify_recovery_code!(code), "Unused recovery code '#{code}' should be valid"
      assert_equal false, @org_provider.verify_recovery_code!(code), "Used recovery code '#{code}' should NOT be valid"
    end

    test "formatted recovery codes can be verified" do
      code = @org_provider.formatted_recovery_codes.first
      refute @org_provider.recovery_code_used?(0)

      assert_equal true, @org_provider.verify_recovery_code!(code), "Recovery code '#{code}' should be valid"
      assert @org_provider.recovery_code_used?(0)
    end

    context "audit log" do
      test "org.recovery_code_used is logged when an admin uses a recovery code" do
        code = @org_provider.recovery_code(0)

        assert_performed_audit_entries(count: 1, only: "org.recovery_code_used") do
          @org_provider.verify_recovery_code!(code)
        end
      end

      test "org.recovery_code_failed is logged when an admin uses a non existent recovery code" do
        events = assert_performed_audit_entries(count: 1, only: "org.recovery_code_failed") do
          @org_provider.verify_recovery_code!("non existent code")
        end
        assert_equal "recovery code does not exist", events.first[:reason]
      end

      test "org.recovery_code_failed is logged when an admin uses an already used recovery code" do
        code = @org_provider.recovery_code(0)
        @org_provider.verify_recovery_code!(code)

        events = assert_performed_audit_entries(count: 1, only: "org.recovery_code_failed") do
          @org_provider.verify_recovery_code!(code)
        end
        assert_equal "recovery code already used", events.first[:reason]
      end
    end
  end

  context "business SAML provider recovery codes" do
    test "generates recovery codes on creation" do
      refute_nil @business_provider.secret
      refute_nil @business_provider.recovery_secret
      refute_nil @business_provider.recovery_used_bitfield
      refute_predicate @business_provider, :recovery_codes_viewed?
    end

    test "unused recovery codes can be verified" do
      code = @business_provider.recovery_code(0)
      refute @business_provider.recovery_code_used?(0)

      assert_equal true, @business_provider.verify_recovery_code!(code), "Recovery code '#{code}' should be valid"
      assert @business_provider.recovery_code_used?(0)
    end

    test "used recovery codes cannot be verified" do
      code = @business_provider.recovery_code(0)
      refute @business_provider.recovery_code_used?(0)

      assert_equal true, @business_provider.verify_recovery_code!(code), "Unused recovery code '#{code}' should be valid"
      assert_equal false, @business_provider.verify_recovery_code!(code), "Used recovery code '#{code}' should NOT be valid"
    end

    test "formatted recovery codes can be verified" do
      code = @business_provider.formatted_recovery_codes.first
      refute @business_provider.recovery_code_used?(0)

      assert_equal true, @business_provider.verify_recovery_code!(code), "Recovery code '#{code}' should be valid"
      assert @business_provider.recovery_code_used?(0)
    end

    context "audit log" do
      test "business.recovery_code_used is logged when an admin uses a recovery code" do
        code = @business_provider.recovery_code(0)

        assert_performed_audit_entries(count: 1, only: "business.recovery_code_used") do
          @business_provider.verify_recovery_code!(code)
        end
      end

      test "business.recovery_code_failed is logged when an admin uses a non existent recovery code" do
        events = assert_performed_audit_entries(count: 1, only: "business.recovery_code_failed") do
          @business_provider.verify_recovery_code!("non existent code")
        end
        assert_equal "recovery code does not exist", events.first[:reason]
      end

      test "business.recovery_code_failed is logged when an admin uses an already used recovery code" do
        code = @business_provider.recovery_code(0)
        @business_provider.verify_recovery_code!(code)

        events = assert_performed_audit_entries(count: 1, only: "business.recovery_code_failed") do
          @business_provider.verify_recovery_code!(code)
        end
        assert_equal "recovery code already used", events.first[:reason]
      end
    end
  end

  context "business OIDC provider recovery codes" do
    test "generates recovery codes on creation", skip_enterprise: true do
      refute_nil @oidc_provider.secret
      refute_nil @oidc_provider.recovery_secret
      refute_nil @oidc_provider.recovery_used_bitfield
      refute_predicate @oidc_provider, :recovery_codes_viewed?
    end

    test "unused recovery codes can be verified", skip_enterprise: true do
      code = @oidc_provider.recovery_code(0)
      refute @oidc_provider.recovery_code_used?(0)

      assert_equal true, @oidc_provider.verify_recovery_code!(code), "Recovery code '#{code}' should be valid"
      assert @oidc_provider.recovery_code_used?(0)
    end

    test "used recovery codes cannot be verified", skip_enterprise: true do
      code = @oidc_provider.recovery_code(0)
      refute @oidc_provider.recovery_code_used?(0)

      assert_equal true, @oidc_provider.verify_recovery_code!(code), "Unused recovery code '#{code}' should be valid"
      assert_equal false, @oidc_provider.verify_recovery_code!(code), "Used recovery code '#{code}' should NOT be valid"
    end

    test "formatted recovery codes can be verified", skip_enterprise: true do
      code = @oidc_provider.formatted_recovery_codes.first
      refute @oidc_provider.recovery_code_used?(0)

      assert_equal true, @oidc_provider.verify_recovery_code!(code), "Recovery code '#{code}' should be valid"
      assert @oidc_provider.recovery_code_used?(0)
    end

    context "audit log", skip_enterprise: true do
      test "business.recovery_code_used is logged when an admin uses a recovery code" do
        code = @oidc_provider.recovery_code(0)

        assert_performed_audit_entries(count: 1, only: "business.recovery_code_used") do
          @oidc_provider.verify_recovery_code!(code)
        end
      end

      test "business.recovery_code_failed is logged when an admin uses a non existent recovery code" do
        events = assert_performed_audit_entries(count: 1, only: "business.recovery_code_failed") do
          @oidc_provider.verify_recovery_code!("non existent code")
        end
        assert_equal "recovery code does not exist", events.first[:reason]
      end

      test "business.recovery_code_failed is logged when an admin uses an already used recovery code" do
        code = @oidc_provider.recovery_code(0)
        @oidc_provider.verify_recovery_code!(code)

        events = assert_performed_audit_entries(count: 1, only: "business.recovery_code_failed") do
          @oidc_provider.verify_recovery_code!(code)
        end
        assert_equal "recovery code already used", events.first[:reason]
      end
    end
  end
end
