# frozen_string_literal: true

require "test_helper"

class AdvisoryReviewsTwoStageApprovalsStageTest < ActiveSupport::TestCase
  def setup
    @label = "approve"
    @disabled = false
    @icon = "check"
    @action = "approve"
    @past_tense_action = "approved"
    @scheme = "danger"
    @confirmation_url = "/confirm"
    @confirmation_params = { key: "value" }
    @test_selector = "test-selector"
    @stage = AdvisoryReviews::TwoStageApprovals::Stage.new(
      label: @label,
      disabled: @disabled,
      icon: @icon,
      action: @action,
      past_tense_action: @past_tense_action,
      scheme: @scheme,
      confirmation_url: @confirmation_url,
      confirmation_params: @confirmation_params,
      test_selector: @test_selector,
    )
    @approval_context = mock("AdvisoryReviews::TwoStageApprovals::ApprovalComponent")
    @approval_context_slug = :stage_one
  end

  def set_approval_context!
    @stage.set_approval_context!(@approval_context_slug, @approval_context)
  end

  test "attributes returns hash of stage specific KVPs" do
    @stage.expects(:target_dialog_id).returns("dialog-id")
    expected_attributes = {
      aria: {
        disabled: @disabled,
        haspopup: true,
      },
      data: {
        "show-dialog-id": "dialog-id",
        targets: "form-tracker.disableWhenChanged",
      },
      inactive: @disabled,
      scheme: @scheme,
      test_selector: @test_selector,
    }
    assert_equal expected_attributes, @stage.attributes
  end

  test "target dialog raises error if approval context was not set" do
    assert_raises(@stage.class::MissingContextError) { @stage.target_dialog }
  end

  test "target dialog uses approval context" do
    set_approval_context!
    @approval_context.expects(:target_dialog).with(@approval_context_slug).returns("dialog")
    assert_equal "dialog", @stage.target_dialog
  end

  test "target dialog id raises error if approval context was not set" do
    assert_raises(@stage.class::MissingContextError) { @stage.target_dialog_id }
  end

  test "target dialog id uses approval context" do
    set_approval_context!
    @approval_context.expects(:target_dialog_id).with(@approval_context_slug).returns("dialog-id")
    assert_equal "dialog-id", @stage.target_dialog_id
  end

  test "icon raises error if approval context was not set" do
    assert_raises(@stage.class::MissingContextError) { @stage.icon }
  end

  test "icon uses approval context" do
    set_approval_context!
    @approval_context.expects(:icon).with(@approval_context_slug).returns("icon")
    assert_equal "icon", @stage.icon
  end

  test "button attributes raises error if approval context was not set" do
    assert_raises(@stage.class::MissingContextError) { @stage.button_attributes }
  end

  test "button attributes uses approval context" do
    set_approval_context!
    @approval_context.expects(:button_attributes).with(@approval_context_slug).returns({ foo: :bar })
    assert_equal({ foo: :bar }, @stage.button_attributes)
  end
end
