# typed: true
# frozen_string_literal: true

require "test_helper"

class OnboardingOrganizationTest < GitHub::TestCase
  fixtures do
    @org = create(:organization, show_onboarding_tasks: nil)
    @emu = create :emu
    @emu_business = @emu.enterprise_managed_business
    @emu_org = create :enterprise_linked_organization, business: @emu_business, admin: @emu
  end

  context "enabled?" do
    test "returns true if show_onboarding_tasks is nil and org is part of startup program" do
      create(:business, :part_of_startups_program, organizations: [@org])

      assert Onboarding::Organization.new(@org.reload).enabled?
    end

    test "returns true if show_onboarding_tasks is nil and org is on enterprise trial" do
      create(:business, trial_expires_at: 1.month.from_now, organizations: [@org])

      assert Onboarding::Organization.new(@org.reload).enabled?
    end

    test "returns true if show_onboarding_tasks is true" do
      @org.update!(show_onboarding_tasks: true)

      assert Onboarding::Organization.new(@org.reload).enabled?
    end

    test "returns false if show_onboarding_tasks is false" do
      @org.update!(show_onboarding_tasks: false)

      refute Onboarding::Organization.new(@org.reload).enabled?
    end

    test "returns false if org is an EMU org" do
      refute Onboarding::Organization.new(@emu_org).enabled?
    end
  end
end unless GitHub.enterprise?
