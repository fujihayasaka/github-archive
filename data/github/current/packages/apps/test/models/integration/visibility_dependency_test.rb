# typed: true
# frozen_string_literal: true

require "test_helper"

class Integration::VisibilityDependencyTest < GitHub::TestCase

  fixtures do
    @user = create(:user)
    @integration = create :integration, :with_active_hook, owner: @user
  end

  context "dual writing" do
    test "public with boolean" do
      integration = create(:integration, public: true)
      assert_equal "public_visibility", integration.visibility
    end

    test "public with string" do
      integration = create(:integration, public: "true")
      assert_equal "public_visibility", integration.visibility
    end

    test "private with boolean" do
      integration = create(:integration, public: false)
      assert_equal "private_visibility", integration.visibility
    end

    test "private with string" do
      integration = create(:integration, public: "false")
      assert_equal "private_visibility", integration.visibility
    end

    test "internal_visibility" do
      business = create(:business, name: "Busy Biz")
      integration = create(:integration, owner: business, visibility: "internal_visibility")
      refute_predicate integration, :public?
    end

    test "private_visibility" do
      integration = create(:integration, visibility: "private_visibility")
      refute_predicate integration, :public?
    end

    test "public_visibility" do
      integration = create(:integration, visibility: "public_visibility")
      assert_predicate integration, :public?
    end

    test "updates" do
      integration = create(:integration, visibility: "private_visibility")
      refute_predicate integration, :public?

      integration.update(public: true)
      assert_predicate integration, :public?

      integration.update(visibility: "internal_visibility")
      refute_predicate integration, :public?
    end
  end

  context "#internal_visibility" do
    test "asserts the integration has internal visibility" do
      business = create(:business, name: "Busy Biz")
      GitHub.flipper[:enterprise_owned_app_management].enable(business)
      integration = create(:integration, owner: business, visibility: "internal_visibility")

      refute_predicate integration, :public_visibility?
      refute_predicate integration, :private_visibility?
      assert_predicate integration, :internal_visibility?
    end
  end

  context "#can_make_private?" do
    test "returns true if there are no installations", skip_with_all_emus: true do
      refute @integration.installations.any?

      assert_predicate @integration, :can_make_private?
    end

    test "returns true if the integration is only installed on the owning account", skip_with_all_emus: true do
      @integration.install_on(@user, repositories: [create(:repository, :minimal, owner: @user)], installer: @user, entry_point: :test_case)

      assert_predicate @integration, :can_make_private?
    end

    test "returns false if the integration is already installed on an external account", skip_with_all_emus: true do
      other_account = create(:user)
      @integration.install_on(other_account, repositories: [create(:repository, :minimal, owner: other_account)], installer: other_account, entry_point: :test_case)

      refute_predicate @integration, :can_make_private?
    end

    test "returns false if the integration has a listing", skip_with_all_emus: true do
      create(:integration_listing, integration: @integration)
      refute_predicate @integration, :can_make_private?
    end

    test "returns false if the integration owner is enterprise managed" do
      @integration.owner.stubs(:is_enterprise_managed?).returns(true)
      refute_predicate @integration, :can_make_private?
    end

    test "returns false if the integration owner is an enterprise" do
      GitHub.flipper[:enterprise_owned_app_management].enable
      integration = create :enterprise_owned_integration
      refute_predicate integration, :can_make_private?
    end
  end

  context "#validate_visibility" do
    test "validates that enterprise_owned integrations cannout be public" do
      GitHub.flipper[:enterprise_owned_app_management].enable
      integration = create :enterprise_owned_integration

      integration.visibility = "public_visibility"
      refute integration.valid?
      assert_equal ["cannot be public"], integration.errors[:visibility]
    end

    test "validates that EMU-owned integrations must be public" do
      @integration.owner.stubs(:is_enterprise_managed?).returns(true)
      @integration.public = false

      refute @integration.valid?
      assert_equal ["cannot be private"], @integration.errors[:public]
    end if TestEnv.test_with_all_emus?

    test "validates non-EMU-owned integrations when making private", skip_with_all_emus: true do
      # for non-EMU owned integrations only validate if
      # the app is being made private
      # https://github.com/github/ecosystem-apps/issues/5426
      @integration.install_on(@user, repositories: [], installer: @user, entry_point: :test_case)
      other_account = create(:user)
      @integration.install_on(other_account, repositories: [], installer: other_account, entry_point: :test_case)
      @integration.public = false

      refute @integration.valid?
      assert_equal ["cannot be private"], @integration.errors[:public]
    end

    test "skips validating non-EMU-owned integrations when updating non-public attributes", skip_with_all_emus: true do
      # for non-EMU owned integrations only validate if
      # the app is being made private
      # https://github.com/github/ecosystem-apps/issues/5426
      @integration.install_on(@user, repositories: [], installer: @user, entry_point: :test_case)
      other_account = create(:user)
      @integration.install_on(other_account, repositories: [], installer: other_account, entry_point: :test_case)
      @integration.update_attribute!(:public, false)

      @integration.update(description: "new description")
      assert @integration.valid?
      assert_empty @integration.errors[:public]
    end
  end

  context "#make_public" do
    test "updates the integration to be public" do
      @integration.update_attribute :public, false
      refute_predicate @integration, :public?

      @integration.make_public

      assert_predicate @integration, :public?
      assert_predicate @integration.reload, :public?
    end

    test "is idempotent" do
      @integration.update_attribute :public, false
      refute_predicate @integration, :public?

      @integration.make_public
      assert_predicate @integration, :public?

      @integration.make_public
      assert_predicate @integration, :public?
    end
  end

  context "#make_private" do
    test "updates the integration to be private" do
      assert_predicate @integration, :public?

      @integration.make_private

      refute_predicate @integration, :public?
      refute_predicate @integration.reload, :public?
    end

    test "is idempotent" do
      assert_predicate @integration, :public?

      @integration.make_private
      refute_predicate @integration, :public?

      @integration.make_private
      refute_predicate @integration, :public?
    end

    test "is not allowed if integration already installed on external accounts" do
      external_account = create(:user)
      @integration.install_on external_account,
        installer: external_account,
        repositories: [create(:repository, :minimal, owner: external_account)],
        entry_point: :test_case

      assert_predicate @integration, :public?
      refute_predicate @integration, :can_make_private?

      refute @integration.make_private

      assert_predicate @integration.reload, :public?
    end
  end
end
