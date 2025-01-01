# typed: true
# frozen_string_literal: true

require "test_helper"

class Integration::Transfers::TransferOwnershipTest < GitHub::TestCase
  def setup
    @integration = create(:integration)
    @target = create(:organization)
    @requester = create(:user)
    @responder = @requester
    @stafftools_initiated = false
    @entry_point = :test_case
  end

  test "calls 'transfer_ownership_to' on integration when transfer is not restricted" do
    Integration::Transfers::Validator.expects(:new).
      with(integration: @integration, target: @target, stafftools_initiated: @stafftools_initiated).
      returns(stub(valid?: true))

    @integration.expects(:transfer_ownership_to).
      with(@target, requester: @requester, responder: @responder, entry_point: @entry_point, stafftools_initiated: @stafftools_initiated)

    transfer = Integration::Transfers::TransferOwnership.new(
      integration: @integration,
      target: @target,
      requester: @requester,
      responder: @responder,
      entry_point: @entry_point,
      stafftools_initiated: @stafftools_initiated
    )

    result = transfer.perform

    assert result.success?
    assert_equal "Transfer completed", result.message
  end

  test "returns failure result when transfer is restricted" do
    Integration::Transfers::Validator.expects(:new).
      with(integration: @integration, target: @target, stafftools_initiated: @stafftools_initiated).
      returns(stub(valid?: false))

    @integration.expects(:transfer_ownership_to).never

    transfer = Integration::Transfers::TransferOwnership.new(
      integration: @integration,
      target: @target,
      requester: @requester,
      responder: @responder,
      entry_point: @entry_point,
      stafftools_initiated: @stafftools_initiated
    )

    result = transfer.perform

    refute result.success?
    assert_equal "Invalid transfer", result.message
  end
end
