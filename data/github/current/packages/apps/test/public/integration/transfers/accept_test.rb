# typed: true
# frozen_string_literal: true

require "test_helper"

class Integration::Transfers::AcceptTest < GitHub::TestCase
  fixtures do
    @integration = create(:integration)
    @target = create(:organization)
    @requester = create(:user)
    @responder = @target.admins.first
  end

  test "calls #finish on transfer object and returns success result when transfer is not restricted" do
    transfer = IntegrationTransfer.create!(
      integration: @integration,
      target: @target,
      requester: @requester
    )

    Integration::Transfers::Validator.expects(:new).
      with(integration: @integration, target: @target, stafftools_initiated: false).
      returns(stub(valid?: true))

    transfer.expects(:finish).with(@responder, entry_point: :test_case)

    result = Integration::Transfers::Accept.perform(
      transfer: transfer,
      responder: @responder,
      entry_point: :test_case,
      stafftools_initiated: false
    )

    assert result.success?
    assert_equal "Transfer completed", result.message
  end

  test "returns failure result and does not finish the transfer when transfer is restricted" do
    transfer = IntegrationTransfer.create!(
      integration: @integration,
      target: @target,
      requester: @requester
    )

    Integration::Transfers::Validator.expects(:new).
      with(integration: @integration, target: @target, stafftools_initiated: false).
      returns(stub(valid?: false))

    transfer.expects(:finish).never

    result = Integration::Transfers::Accept.perform(
      transfer: transfer,
      responder: @responder,
      entry_point: :test_case,
      stafftools_initiated: false
    )

    refute result.success?
    assert_equal "Invalid transfer", result.message
  end
end
