# typed: true
# frozen_string_literal: true

require "test_helper"

class IntegrationTransfersExecutorTest < GitHub::TestCase
  fixtures do
    @integration = create(:integration)
    @target = create(:organization)
    @requester = create(:user)
    @responder = @target.admins.first
  end

  test "returns a failure result if transfer is not cancellable" do
    transfer = IntegrationTransfer.create!(
      integration: @integration,
      target: @target,
      requester: @requester,
    )
    transfer.expects(:cancelable_by?).with(@responder).returns(false)

    executor  = Integration::Transfers::Executor.new(transfer, @responder)

    result = executor.cancel!

    refute result.success?
    assert_equal "Cannot be cancelled by user", result.message
  end

  test "calls #cancel on transfer object" do
    transfer = IntegrationTransfer.create!(
      integration: @integration,
      target: @target,
      requester: @requester,
    )
    transfer.expects(:cancelable_by?).with(@responder).returns(true)
    transfer.expects(:destroy).returns(true)

    executor  = Integration::Transfers::Executor.new(transfer, @responder)

    result = executor.cancel!

    assert result.success?
    assert_equal "Transfer cancelled", result.message
  end
end
