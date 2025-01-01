# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::ExtensionsAgreementSignatureTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  fixtures do
    @user = create(:user)
    @org = create(:organization)
    @business = create(:business)
  end

  context ".sign!" do
    context "when not passing in a signature context" do
      test "creates a signature record for just the signatory" do
        assert_changes -> { Copilot::ExtensionsAgreementSignature.count }, 1 do
          signature = Copilot::ExtensionsAgreementSignature.sign!(signatory: @user)

          assert_equal @user, signature.signatory
          assert_nil signature.organization
          assert_nil signature.business
        end
      end
    end

    context "when passing in a user as the signature context" do
      test "creates a signature record for just the signatory" do
        assert_changes -> { Copilot::ExtensionsAgreementSignature.count }, 1 do
          signature = Copilot::ExtensionsAgreementSignature.sign!(signatory: @user, context: create(:user))

          assert_equal @user, signature.signatory
          assert_nil signature.organization
          assert_nil signature.business
        end
      end
    end

    context "when passing in an organization as the signature context" do
      test "creates a signature record for the user and the organization" do
        assert_changes -> { Copilot::ExtensionsAgreementSignature.count }, 1 do
          signature = Copilot::ExtensionsAgreementSignature.sign!(signatory: @user, context: @org)

          assert_equal @user, signature.signatory
          assert_equal @org, signature.organization
          assert_nil signature.business
        end
      end
    end

    context "when passing in a business as the signature context" do
      test "creates a signature record for the user and the business" do
        assert_changes -> { Copilot::ExtensionsAgreementSignature.count }, 1 do
          signature = Copilot::ExtensionsAgreementSignature.sign!(signatory: @user, context: @business)

          assert_equal @user, signature.signatory
          assert_nil signature.organization
          assert_equal @business, signature.business
        end
      end
    end
  end

  context ".signed_by?" do
    context "when the context is a user" do
      test "true if there is a signature record for the user" do
        Copilot::ExtensionsAgreementSignature.create(signatory: @user)

        assert Copilot::ExtensionsAgreementSignature.signed_by?(@user)
      end

      test "false if there is no signature record for the user" do
        refute Copilot::ExtensionsAgreementSignature.signed_by?(@user)
      end
    end

    context "when the context is an organization" do
      test "true if there is a signature record for the organization" do
        Copilot::ExtensionsAgreementSignature.create(signatory: @user, organization: @org)

        assert Copilot::ExtensionsAgreementSignature.signed_by?(@org)
      end

      test "false if there is no signature record for the organization" do
        refute Copilot::ExtensionsAgreementSignature.signed_by?(@org)
      end
    end

    context "when the context is a business" do
      test "true if there is a signature record for the business" do
        Copilot::ExtensionsAgreementSignature.create(signatory: @user, business: @business)

        assert Copilot::ExtensionsAgreementSignature.signed_by?(@business)
      end

      test "false if there is no signature record for the business" do
        refute Copilot::ExtensionsAgreementSignature.signed_by?(@business)
      end
    end
  end
end if GitHub.copilot_enabled?
