# typed: true
# frozen_string_literal: true

require "test_helper"

class Conduit::ExpContextTest < GitHub::TestCase
  fixtures do
    @viewer = create(:user)
  end

  context "#sticky_announcements_enabled?" do
    test "when enrolled in the experiment" do
      AzureEXP::Experiments.stubs(:sticky_announcements_enabled?).returns(true)
      exp_context = ::Conduit::ExpContext.new(@viewer)
      assert_predicate exp_context, :sticky_announcements_enabled?
    end

    test "when not enrolled in the experiment" do
      AzureEXP::Experiments.stubs(:sticky_announcements_enabled?).returns(false)
      exp_context = ::Conduit::ExpContext.new(@viewer)
      refute_predicate exp_context, :sticky_announcements_enabled?
    end
  end
end
