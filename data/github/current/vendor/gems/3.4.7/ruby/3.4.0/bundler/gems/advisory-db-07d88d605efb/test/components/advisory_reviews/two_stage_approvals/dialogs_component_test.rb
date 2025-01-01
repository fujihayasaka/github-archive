# frozen_string_literal: true

require "test_helper"

class AdvisoryReviewsTwoStageApprovalsDialogsComponentTest < ViewComponent::TestCase
  def setup
    namespace = AdvisoryReviews::TwoStageApprovals
    @subject = namespace::DialogsComponent
    @stage_one = namespace::Stage.new(label: "one", disabled: false, icon: :play, action: "first", past_tense_action: "firsted", confirmation_url: "#", test_selector: "test-selector-stage-one")
    @stage_two = namespace::Stage.new(label: "two", disabled: false, icon: :stop, action: "second", past_tense_action: "seconded", confirmation_url: "#", test_selector: "test-selector-stage-two")
    @approval_group = namespace::ApprovalComponent.new(stage_one: @stage_one, stage_two: @stage_two)
    @approval_group.stubs(:guid).returns("test-guid")
    @component = @subject.new(approval_group: @approval_group)
  end

  test "knows which dialogs to show based on stage context" do
    @stage_one.stubs(:target_dialog).returns(:dialog_one)
    @stage_two.stubs(:target_dialog).returns(:dialog_two)
    assert @component.show_dialog?(:dialog_one)
    assert @component.show_dialog?(:dialog_two)
    refute @component.show_dialog?(:dialog_three)
  end

  test "dialog id combines approval group guid and target dialog slug" do
    target_dialog_slug = :dialog_one
    expected_id = "dialog-dialog-one-test-guid"
    assert_equal expected_id, @component.dialog_id(target_dialog_slug)
  end

  test "test selector uses target dialog slug" do
    target_dialog_slug = :dialog_one
    expected_selector = "dialog-dialog-one"
    assert_equal expected_selector, @component.test_selector(target_dialog_slug)
  end

  test "renders" do
    render_inline(@component)
  end

  test "renders confirmation preamble for stage two" do
    @stage_one.stubs(:disabled?).returns(true)
    @component.with_stage_two_confirmation_preamble_content("We the People...")
    render_inline(@component)
    assert_selector "[data-test-selector='dialog-stage-two-confirmation']", text: "We the People..."
  end

  test "renders confirmation diff for stage two" do
    @stage_one.stubs(:disabled?).returns(true)
    @component.with_stage_two_confirmation_diff_content("- assert_equal foo, bar\n+ assert_equal flu, bat")
    render_inline(@component)
    assert_selector "[data-test-selector='dialog-stage-two-confirmation']", text: "- assert_equal foo, bar\n+ assert_equal flu, bat"
  end
end
