# typed: true
# frozen_string_literal: true

require "test_helper"

class IntegrationTransfersServiceTest < GitHub::TestCase
  fixtures do
    @integration = create(:integration)
    @target = create(:organization)
    @requester = create(:user)
  end

  setup do
    @validator = Minitest::Mock.new
    @initiator = Minitest::Mock.new
    @executor = Minitest::Mock.new
  end

  test "calls #start! when validation passes" do
    success_result = Integration::Transfers::Result.success(@integration, "Transfer started")

    Integration::Transfers::Initiator.stub :new, @initiator do
      @initiator.expect(:start!, success_result)

      result = Integration::Transfers::Service.start!(
        integration: @integration,
        target: @target,
        requester: @requester
      )

      assert result.success?
      assert_equal @integration, result.integration

      @initiator.verify
    end
  end

  test "can_transfer? delegates to validator" do
    Integration::Transfers::Validator.stub :new, @validator do
      @validator.expect(:valid?, true)

      assert Integration::Transfers::Service.can_transfer?(
        integration: @integration,
        target: @target
      )

      @validator.verify
    end
  end

  test "finish! delegates to Accept" do
    transfer = IntegrationTransfer.create!(integration: @integration, target: @target, requester: @requester)
    expected_result = Integration::Transfers::Result.success(@integration, "Transfer completed")

    Integration::Transfers::Accept.expects(:perform).with(
      transfer: transfer,
      responder: @requester,
      entry_point: :test_case,
      stafftools_initiated: false
    ).returns(expected_result)

    result = Integration::Transfers::Service.finish!(
      xfer: transfer,
      responder: @requester,
      entry_point: :test_case
    )
    assert_equal expected_result, result
  end

  test "cancel! delegates to executor" do
    transfer = IntegrationTransfer.create!(integration: @integration, target: @target, requester: @requester)
    success_result = Integration::Transfers::Result.success(@integration, "Transfer cancelled")

    Integration::Transfers::Executor.stub :new, @executor do
      @executor.expect(:cancel!, success_result)

      result = Integration::Transfers::Service.cancel!(
        xfer: transfer,
        responder: @requester
      )

      assert result.success?
      @executor.verify
    end
  end

  test "stafftools_initiated flag is passed through to validator" do
    Integration::Transfers::Validator.stub :new, @validator,
      [:integration, :target, :requester, stafftools_initiated: true] do
      @validator.expect(:valid?, true)

      result = Integration::Transfers::Service.can_transfer?(
        integration: @integration,
        target: @target,
        stafftools_initiated: true
      )

      assert result
      @validator.verify
    end

  end

  context ".stafftools_transfer_ownership" do
    test "calls TransferOwnership.perform with stafftools_initiated: true" do
      expected_result = Integration::Transfers::Result.success(@integration, "Transfer completed")
      Integration::Transfers::TransferOwnership.expects(:perform).with(
        integration: @integration,
        target: @target,
        requester: @requester,
        responder: @requester,
        entry_point: :test_case,
        stafftools_initiated: true
      ).returns(expected_result)

      result = Integration::Transfers::Service.stafftools_transfer_ownership(
        integration: @integration,
        target: @target,
        staff_user: @requester,
        entry_point: :test_case
      )
      assert_equal expected_result, result
    end
  end
end
