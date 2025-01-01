# typed: true
# frozen_string_literal: true

require "test_helper"

class ExperimentDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
  end

  context "#assigned?" do
    test "returns true if user assigned the variant" do
      AzureEXP::Experiments::Assignments.any_instance.stubs(:assigned?).returns(true)

      assert @user.assigned?(:experiment)
    end

    test "returns false if user not assigned the variant" do
      AzureEXP::Experiments::Assignments.any_instance.stubs(:assigned?).returns(false)

      refute @user.assigned?(:experiment)
    end

    test "only requests assignment once" do
      AzureEXP::Experiments::Assignments.any_instance.expects(:assigned?).once.returns(true)

      assert @user.assigned?(:experiment)
      assert @user.assigned?(:experiment)
    end

    test "calls assignment with each variant" do
      AzureEXP::Experiments::Assignments.any_instance.expects(:assigned?).times(3).returns(true)

      assert @user.assigned?(:experiment, variant: "A")
      assert @user.assigned?(:experiment, variant: "B")
      assert @user.assigned?(:experiment, variant: "C")
    end
  end
end
