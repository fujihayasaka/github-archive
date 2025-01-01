# frozen_string_literal: true

require "test_helper"

class AdvisoryReviewsTwoStageApprovalsApprovalComponentTest < ViewComponent::TestCase
  def setup
    namespace = AdvisoryReviews::TwoStageApprovals
    @subject = namespace::ApprovalComponent
    @stage_one = namespace::Stage.new(label: "one", disabled: false, icon: :play, action: "first", past_tense_action: "firsted", confirmation_url: "#", test_selector: "test-selector-stage-one")
    @stage_two = namespace::Stage.new(label: "two", disabled: false, icon: :stop, action: "second", past_tense_action: "seconded", confirmation_url: "#", test_selector: "test-selector-stage-two")
    @dialogs_component_class = namespace::DialogsComponent
    @component = @subject.new(stage_one: @stage_one, stage_two: @stage_two)
  end

  test "sets the stage" do
    assert_equal @stage_one, @component.stage_one
    assert_equal @stage_two, @component.stage_two
  end

  test "generates a memoized guid for the approval group" do
    guid = @component.guid
    assert_match(/\A[\da-f]{8}-([\da-f]{4}-){3}[\da-f]{12}\z/, guid)
    assert_equal @component.guid, guid
  end

  test "determines target dialog slugs with both stages disabled" do
    @stage_one.stubs(:disabled?).returns(true)
    @stage_two.stubs(:disabled?).returns(true)
    assert_equal @dialogs_component_class::BOTH_STAGES_PENDING, @component.target_dialog(:stage_one)
    assert_equal @dialogs_component_class::BOTH_STAGES_PENDING, @component.target_dialog(:stage_two)
  end

  test "determines target dialog slugs with stage one disabled and stage two enabled" do
    @stage_one.stubs(:disabled?).returns(true)
    assert_equal @dialogs_component_class::STAGE_ONE_ALREADY_COMPLETE, @component.target_dialog(:stage_one)
    assert_equal @dialogs_component_class::STAGE_TWO_CONFIRMATION, @component.target_dialog(:stage_two)
  end

  test "determines target dialog slugs with stage one enabled and stage two disabled" do
    @stage_two.stubs(:disabled?).returns(true)
    assert_equal @dialogs_component_class::STAGE_ONE_CONFIRMATION, @component.target_dialog(:stage_one)
    assert_equal @dialogs_component_class::PENDING_STAGE_ONE, @component.target_dialog(:stage_two)
  end

  test "generates target dialog ids with both stages disabled" do
    @stage_one.stubs(:disabled?).returns(true)
    @stage_two.stubs(:disabled?).returns(true)
    @component.stubs(:guid).returns("test-guid")
    assert_equal "dialog-both-stages-pending-test-guid", @component.target_dialog_id(:stage_one)
    assert_equal "dialog-both-stages-pending-test-guid", @component.target_dialog_id(:stage_two)
  end

  test "generates target dialog ids with stage one disabled and stage two enabled" do
    @stage_one.stubs(:disabled?).returns(true)
    @component.stubs(:guid).returns("test-guid")
    assert_equal "dialog-stage-one-already-complete-test-guid", @component.target_dialog_id(:stage_one)
    assert_equal "dialog-stage-two-confirmation-test-guid", @component.target_dialog_id(:stage_two)
  end

  test "generates target dialog ids with stage one enabled and stage two disabled" do
    @stage_two.stubs(:disabled?).returns(true)
    @component.stubs(:guid).returns("test-guid")
    assert_equal "dialog-stage-one-confirmation-test-guid", @component.target_dialog_id(:stage_one)
    assert_equal "dialog-pending-stage-one-test-guid", @component.target_dialog_id(:stage_two)
  end

  test "determines the appropriate icons with both stages disabled" do
    @stage_one.stubs(:disabled?).returns(true)
    @stage_two.stubs(:disabled?).returns(true)
    assert_equal :lock, @component.icon(:stage_one)
    assert_equal :lock, @component.icon(:stage_two)
  end

  test "determines the appropriate icons with stage one disabled and stage two enabled" do
    @stage_one.stubs(:disabled?).returns(true)
    assert_equal :"check-circle-fill", @component.icon(:stage_one)
    assert_equal :stop, @component.icon(:stage_two)
  end

  test "determines the appropriate icons with stage one enabled and stage two disabled" do
    @stage_two.stubs(:disabled?).returns(true)
    assert_equal :play, @component.icon(:stage_one)
    assert_equal :lock, @component.icon(:stage_two)
  end

  test "combines common button attributes with stage specific attributes and stage one positioning attributes" do
    @component.stubs(:common_button_attributes).returns({ biz: :bang })
    @stage_one.stubs(:attributes).returns({ foo: :bar })
    @component.stubs(:stage_one_position_attributes).returns({ ding: :bat })
    assert_equal({ biz: :bang, foo: :bar, ding: :bat }, @component.button_attributes(:stage_one))
  end

  test "combines common button attributes with stage specific attributes and stage two positioning attributes" do
    @component.stubs(:common_button_attributes).returns({ biz: :bang })
    @stage_two.stubs(:attributes).returns({ fluff: :bun })
    @component.stubs(:stage_two_position_attributes).returns({ bing: :bong })
    assert_equal({ biz: :bang, fluff: :bun, bing: :bong }, @component.button_attributes(:stage_two))
  end

  test "renders the component" do
    render_inline(@component)
    assert_selector "[data-test-selector='test-selector-stage-one']", text: "One"
    assert_selector "[data-test-selector='test-selector-stage-two']", text: "Two"
  end

  test "makes stage one button inactive if disabled" do
    @stage_one.stubs(:disabled?).returns(true)
    render_inline(@component)
    assert_selector "[data-test-selector='test-selector-stage-one'][aria-disabled]", count: 1
  end

  test "makes stage two button inactive if disabled" do
    @stage_two.stubs(:disabled?).returns(true)
    render_inline(@component)
    assert_selector "[data-test-selector='test-selector-stage-two'][aria-disabled]", count: 1
  end
end
