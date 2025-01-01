# typed: false
# frozen_string_literal: true
require "test_helper"

class EnforcerTest < GitHub::TestCase
  include DogstatsTestHelpers
  TestError = Class.new(StandardError)

  fixtures do
    @org = create(:organization)
    @repo = create(:repository, :minimal, owner: @org)
    @user = create(:user)
    @business = create(:business)
  end

  setup do
    @callback = Object.new

    ConditionalAccess::Enforcer.any_instance.stubs(:location).returns(:test)
    ConditionalAccess::Enforcer.any_instance.stubs(:callback_name).returns("Object")
    @enforcer = ConditionalAccess::Enforcer.new(@callback)

    @enforcer.stubs(:location).returns(:test)
    @enforcer.stubs(:conditional_access_policies).returns([:test])
    @enforcer.stubs(:registered_policies).returns([:test])
  end

  context "enforceable" do
    test "dispatches to implementation" do
      @callback.stubs(:test_enforceable).returns(:yes)
      assert_equal :yes, @enforcer.send(:enforceable, :test)

      @callback.stubs(:test_enforceable).returns(:no)
      assert_equal :no, @enforcer.send(:enforceable, :test)
    end

    test "defaults to :yes if method is not implemented" do

      refute respond_to?(:test_enforceable)
      assert_equal :yes, @enforcer.send(:enforceable, :test)
    end

    test "raises if attempting to dispatch to an unregistered policies" do

      assert_raises ConditionalAccess::Enforcer::Error do
        @enforcer.send(:enforceable, :testing)
      end
    end

    test "raises if dispatched method returns invalid decision" do
      @callback.stubs(:test_enforceable).returns(nil)

      assert_raises ConditionalAccess::Enforcer::Error do
        @enforcer.send(:enforceable, :testing)
      end
    end

    test "does not call target_for_conditional_access method if no policy is enforceable" do
      @callback.stubs(:test_enforceable).returns(:no)

      @enforcer.expects(:safe_target_for_conditional_access).never

      @enforcer.evaluate_conditional_access_policies(1)
    end
  end

  context "applicable" do
    test "dispatches to implementation" do

      @callback.stubs(:test_applicable).returns(:yes)
      assert_equal :yes, @enforcer.send(:applicable, @org, :test)

      @callback.stubs(:test_applicable).returns(:no)
      assert_equal :no, @enforcer.send(:applicable, @org, :test)
    end

    test "defaults to :yes if method is not implemented" do

      refute respond_to?(:test_applicable)
      assert_equal :yes, @enforcer.send(:applicable, @org, :test)
    end

    test "raises if attempting to dispatch to an unregistered policies" do

      assert_raises ConditionalAccess::Enforcer::Error do
        @enforcer.send(:applicable, @org, :testing)
      end
    end

    test "raises if dispatched method returns invalid decision" do
      @callback.stubs(:test_applicable).returns(nil)

      assert_raises ConditionalAccess::Enforcer::Error do
        @enforcer.send(:applicable, @org, :testing)
      end
    end
  end

  context "satisfied" do
    test "dispatches to implementation" do

      @callback.stubs(:test_satisfied).returns(:yes)
      assert_equal :yes, @enforcer.send(:satisfied, @org, :test)

      @callback.stubs(:test_satisfied).returns(:no)
      assert_equal :no, @enforcer.send(:satisfied, @org, :test)
    end

    test "defaults to :no if method is not implemented" do

      refute respond_to?(:test_satisfied)
      assert_equal :no, @enforcer.send(:satisfied, @org, :test)
    end

    test "raises if attempting to dispatch to an unregistered policies" do

      assert_raises ConditionalAccess::Enforcer::Error do
        @enforcer.send(:satisfied, @org, :testing)
      end
    end

    test "raises if dispatched method returns invalid decision" do
      @callback.stubs(:test_satisfied).returns(nil)

      assert_raises ConditionalAccess::Enforcer::Error do
        @enforcer.send(:satisfied, @org, :testing)
      end
    end
  end

  context "enforce" do
    test "dispatches to implementation" do

      @callback.stubs(:test_enforce).raises(TestError.new("error"))
      assert_raises TestError do
        @enforcer.send(:enforce, @org, :test)
      end
    end

    test "raises if delegate method is not implemented" do

      refute respond_to?(:test_enforce)
      assert_raises ConditionalAccess::Enforcer::Error do
        @enforcer.send(:enforce, @org, :test)
      end
    end

    test "returns nil" do

      @callback.stubs(:test_enforce).returns(true)
      assert_nil @enforcer.send(:enforce, @org, :test)
    end

    test "raises if attempting to dispatch to an unregistered policies" do

      assert_raises ConditionalAccess::Enforcer::Error do
        assert @enforcer.send(:enforce, @org, :testing)
      end
    end
  end

  context "evaluate_conditional_access_policies" do
    test "raises if resource is nil" do
      assert_raises ConditionalAccess::Enforcer::ResourceError do
        @enforcer.evaluate_conditional_access_policies(nil)
      end
    end

    test "forwards the target for conditional access and resource to workflow methods" do
      @enforcer.expects(:enforceable).with(:test).returns(:yes)
      @enforcer.expects(:applicable).with(@repo, :test).returns(:yes)
      @enforcer.expects(:satisfied).with(@repo, :test).returns(:no)
      @enforcer.evaluate_conditional_access_policies(@repo)
    end

    test "forwards the target for conditional access and resource to the callback" do
      @callback.expects(:test_enforceable).returns(:yes)
      @callback.expects(:test_applicable).with(has_entry(:target_provider, instance_of(ConditionalAccess::TargetProvider))).returns(:yes)
      @callback.expects(:test_satisfied).with(has_entry(:target_provider, instance_of(ConditionalAccess::TargetProvider))).returns(:no)
      @enforcer.evaluate_conditional_access_policies(@repo)
    end

    test "policy fails unless behaviour is defined" do
      assert_equal Hash[:test, :unsatisfied], @enforcer.evaluate_conditional_access_policies(@org)
    end

    test "raises if :registered_policies is not defined" do
      @enforcer.unstub(:registered_policies) do
        assert_raises ConditionalAccess::Enforcer::Error do
          @enforcer.evaluate_conditional_access_policies(@org)
        end
      end
    end

    test "indicates if policy is not enforceable" do
      @enforcer.stubs(:conditional_access_policies).returns([:policy1])
      @enforcer.stubs(:registered_policies).returns([:policy1])

      @callback.expects(:policy1_enforceable).once.returns(:no)
      @callback.expects(:policy1_applicable).never
      @callback.expects(:policy1_satisfied).never
      assert_equal Hash[:policy1, :unenforceable], @enforcer.evaluate_conditional_access_policies(@org)
    end

    test "indicates if policy is not applicable, and continues evaluation" do
      @enforcer.stubs(:conditional_access_policies).returns([:policy1])
      @enforcer.stubs(:registered_policies).returns([:policy1])

      @callback.expects(:policy1_enforceable).once.returns(:yes)
      @callback.expects(:policy1_applicable).once.returns(:no)
      @callback.expects(:policy1_satisfied).never
      assert_equal Hash[:policy1, :inapplicable] , @enforcer.evaluate_conditional_access_policies(@org)
    end

    test "returns unsatisfied if not satisfied" do
      @enforcer.stubs(:conditional_access_policies).returns([:policy1])
      @enforcer.stubs(:registered_policies).returns([:policy1])

      @callback.expects(:policy1_enforceable).once.returns(:yes)
      @callback.expects(:policy1_applicable).once.returns(:yes)
      @callback.expects(:policy1_satisfied).once.returns(:no)
      assert_equal Hash[:policy1, :unsatisfied], @enforcer.evaluate_conditional_access_policies(@org)
    end

    test "returns satisfied if policy is met" do
      @enforcer.stubs(:conditional_access_policies).returns([:policy1])
      @enforcer.stubs(:registered_policies).returns([:policy1])

      @callback.expects(:policy1_enforceable).once.returns(:yes)
      @callback.expects(:policy1_applicable).once.returns(:yes)
      @callback.expects(:policy1_satisfied).once.returns(:yes)
      assert_equal Hash[:policy1, :satisfied], @enforcer.evaluate_conditional_access_policies(@org)
    end

    test "evaluates all policies" do
      @enforcer.stubs(:conditional_access_policies).returns([:policy1, :policy2, :policy3, :policy4])
      @enforcer.stubs(:registered_policies).returns([:policy1, :policy2, :policy3, :policy4])

      @callback.expects(:policy1_applicable).once.returns(:no)
      @callback.expects(:policy2_enforceable).once.returns(:no)
      @callback.expects(:policy3_satisfied).once.returns(:yes)
      @callback.expects(:policy4_satisfied).once.returns(:no)
      assert_equal Hash[:policy1, :inapplicable, :policy2, :unenforceable, :policy3, :satisfied, :policy4, :unsatisfied], @enforcer.evaluate_conditional_access_policies(@org)
    end

    test "returns all failed policies by default" do
      @enforcer.stubs(:conditional_access_policies).returns([:policy1, :policy2])
      @enforcer.stubs(:registered_policies).returns([:policy1, :policy2])

      @callback.expects(:policy1_satisfied).once.returns(:no)
      @callback.expects(:policy2_satisfied).once.returns(:no)
      assert_equal Hash[:policy1, :unsatisfied, :policy2, :unsatisfied], @enforcer.evaluate_conditional_access_policies(@org)
    end

    test "does not continue to evaluate the rest of policies when one fails if fail_fast specified" do
      @enforcer.stubs(:conditional_access_policies).returns([:policy1, :policy2])
      @enforcer.stubs(:registered_policies).returns([:policy1, :policy2])

      @callback.expects(:policy1_satisfied).once.returns(:no)
      @callback.expects(:policy2_enforce).never
      assert_equal Hash[:policy1, :unsatisfied], @enforcer.evaluate_conditional_access_policies(@org, fail_fast: true)
    end

    test "inapplicable and unenforceable policies do not trigger fail_fast" do
      @enforcer.stubs(:conditional_access_policies).returns([:policy1, :policy2, :policy3, :policy4])
      @enforcer.stubs(:registered_policies).returns([:policy1, :policy2, :policy3, :policy4])

      @callback.expects(:policy1_enforceable).once.returns(:no)
      @callback.expects(:policy2_applicable).once.returns(:no)
      @callback.expects(:policy3_satisfied).once.returns(:no)

      # Because of fail_fast, policy4 will never be evaluated!
      @callback.expects(:policy4_enforceable).never
      @callback.expects(:policy4_applicable).never
      @callback.expects(:policy4_satisfied).never

      assert_equal Hash[:policy1, :unenforceable, :policy2, :inapplicable, :policy3, :unsatisfied], @enforcer.evaluate_conditional_access_policies(@org, fail_fast: true)
    end
  end

  context "enforce_conditional_access_policies" do
    test "raises if registered_policies is not defined" do
      @enforcer.unstub(:registered_policies) do
        assert_raises ConditionalAccess::Enforcer::Error do
          @enforcer.evaluate_conditional_access_policies(@org)
        end
      end
    end

    test "returns :ok if there are no policies" do
      @enforcer.stubs(:conditional_access_policies).returns([])
      @enforcer.stubs(:registered_policies).returns([])
      assert_equal :ok, @enforcer.enforce_conditional_access_policies(@org)
    end

    test "returns :ok if all policies are met" do
      @callback.expects(:test_satisfied).once.returns(:yes)
      assert_equal :ok, @enforcer.enforce_conditional_access_policies(@org)
    end

    test "raises when policy does not implement enforce" do
      assert_raises ConditionalAccess::Enforcer::Error do
        @enforcer.enforce_conditional_access_policies(@org)
      end
    end

    test "enforces first failing policy and returns name if policy is not met" do
      @enforcer.stubs(:conditional_access_policies).returns([:test, :nopes])
      @enforcer.stubs(:registered_policies).returns([:test, :nopes])

      @callback.expects(:test_enforce).once.returns(nil)
      @callback.expects(:nopes_enforceable).never
      @callback.expects(:nopes_enforce).never
      assert_equal :test, @enforcer.enforce_conditional_access_policies(@org)
    end
  end

  context "instrumentation" do
    test "enforce emits metrics" do
      @callback.stubs(:test_enforceable).returns(:yes)
      @callback.stubs(:test_applicable).returns(:yes)
      @callback.stubs(:test_satisfied).returns(:no)
      @callback.stubs(:test_enforce).returns(nil)

      @enforcer.enforce_conditional_access_policies(@org)
      assert_dogstats_distribution "cap.enforcer.evaluation.dist", tags: ["location:test", "callback:Object", "cached:false"]
      assert_dogstats_distribution "cap.enforcer.operation.dist", tags: ["policy:test", "operation:enforceable", "location:test", "callback:Object", "decision:yes"]
      assert_dogstats_distribution "cap.enforcer.operation.dist", tags: ["policy:test", "operation:applicable", "location:test", "callback:Object", "decision:yes"]
      assert_dogstats_distribution "cap.enforcer.operation.dist", tags: ["policy:test", "operation:satisfied", "location:test", "callback:Object", "decision:no"]
      assert_dogstats_distribution "cap.enforcer.operation.dist", tags: ["policy:test", "operation:enforce", "location:test", "callback:Object"]
      assert_dogstats_distribution "cap.target_for_conditional_access.dist", tags: ["location:test", "callback:Object", "resource:Organization"], count: 1
      assert_dogstats_count_value 1, "cap.enforcer.executed", tags: ["success:true", "error:"]
    end
  end
end
