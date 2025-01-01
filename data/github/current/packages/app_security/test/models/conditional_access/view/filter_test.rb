# typed: true
# frozen_string_literal: true

require "test_helper"

class ViewFilterTest < GitHub::IntegrationTestCase
  skip_enterprise

  fixtures do
    @user = create(:user)
    @repo = create(:repository, :minimal)

    @emu      = create :emu
    @emu_org  = create :enterprise_linked_organization,
                        business: @emu.enterprise_managed_business,
                        admin: @emu
    @emu_repo = create(:private_repository, :minimal, owner: @emu_org)
  end

  test "safe_request_method? is set to false" do
    controller = TestController.new(current_user: @user)
    filter = ConditionalAccess::View::Filter.new(controller)
    refute filter.safe_request_method?
  end

  context "EmuOwnership #authorized?" do
    test "true for EMU and Business resource (satisfied)" do
      controller = TestController.new(current_user: @emu)
      filter = ConditionalAccess::View::Filter.new(controller)

      assert filter.authorized?(resource: @emu_repo, policy: :emu_ownership)
    end

    test "false for EMU and outside resource (unsatisifed)" do
      controller = TestController.new(current_user: @emu)
      filter = ConditionalAccess::View::Filter.new(controller)

      refute filter.authorized?(resource: @repo, policy: :emu_ownership)
    end

    test "true for non EMU (inapplicable)" do
      controller = TestController.new(current_user: @user)
      filter = ConditionalAccess::View::Filter.new(controller)

      assert filter.authorized?(resource: @repo, policy: :emu_ownership)
    end
  end
end
