# typed: true
# frozen_string_literal: true

require "test_helper"

class EphemeralBillingMessageTest < GitHub::TestCase

  setup do
    @codespace = create(:codespace)
    @billing_message = build(
      :codespace_ephemeral_billing_message,
      codespaces: [@codespace],
      codespace_plan_id: @codespace.plan.id,
      caller_name: "codespaces/dispatch_billing_message"
    )
  end

  context "is_prod_vscs_target?" do
    test "returns true when prod" do
      billing_message = build(
        :codespace_ephemeral_billing_message,
        codespaces: [@codespace],
        codespace_plan_id: @codespace.plan.id,
        caller_name: "codespaces/dispatch_billing_message",
        vscs_target: :production
      )
      assert(billing_message.is_prod_vscs_target?)
    end

    test "returns false when not prod" do
      billing_message = build(
        :codespace_ephemeral_billing_message,
        codespaces: [@codespace],
        codespace_plan_id: @codespace.plan.id,
        caller_name: "codespaces/dispatch_billing_message",
        vscs_target: :ppe
      )
      refute(billing_message.is_prod_vscs_target?)
    end
  end

  context "validations" do
    test "valid" do
      assert @billing_message.valid?
    end

    test "invalid without id" do
      @billing_message.stubs(:id).returns(nil)
      refute @billing_message.valid?
    end

    test "invalid without codespace_plan_id" do
      @billing_message.stubs(:codespace_plan_id).returns(nil)
      refute @billing_message.valid?
    end

    test "invalid without codespace_guids" do
      @billing_message.stubs(:codespace_guids).returns([])
      refute @billing_message.valid?
    end

    test "invalid without caller_name" do
      @billing_message.stubs(:caller_name).returns(nil)
      refute @billing_message.valid?
    end

    test "invalid without created_at" do
      @billing_message.stubs(:created_at).returns(nil)
      refute @billing_message.valid?
    end

    test "invalid with invalid usage report" do
      Codespaces::BillingMessageTrackedUsage.any_instance.stubs(:valid?).returns(false)
      refute @billing_message.valid?
    end

    context "location validation" do
      test "requires a valid location" do
        @billing_message.stubs(:location).returns("India")
        refute @billing_message.valid?
      end
    end
  end
end
