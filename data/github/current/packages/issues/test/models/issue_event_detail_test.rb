# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueEventDetailTest < GitHub::TestCase
  include StringFromBinaryTestHelper

  context "4 byte unicode characters" do
    test "supported by #milestone_title attribute" do
      event = create(:issue_event,
        actor: create(:user), event: "milestoned",
        milestone_title: "𠲖 milestone"
      )

      detail = IssueEventDetail.find_by(id: event.issue_event_detail.id)

      assert_equal "𠲖 milestone", T.must(detail).milestone_title
    end

    test "supported by #title_was attribute" do
      event = create(:issue_event,
        actor: create(:user), event: "milestoned",
        title_was: "𠲖 title"
      )

      detail = IssueEventDetail.find_by(id: event.issue_event_detail.id)

      assert_equal "𠲖 title", T.must(detail).title_was
    end

    test "supported by #title_is attribute" do
      event = create(:issue_event,
        actor: create(:user), event: "milestoned",
        title_is: "𠲖 title"
      )

      detail = IssueEventDetail.find_by(id: event.issue_event_detail.id)

      assert_equal "𠲖 title", T.must(detail).title_is
    end

    test "ref with emoji is truncated" do
      event = create(:issue_event,
        actor: create(:user), event: "milestoned",
        title_is: "𠲖 title",
        ref: "start" + "🐹" + "tail" # rubocop:disable Style/StringConcatenation
      )

      detail = IssueEventDetail.find_by(id: event.issue_event_detail.id)

      assert_equal "start", T.must(detail).ref
    end

    test "ref with over 255 characters is truncated" do
      event = create(:issue_event,
        actor: create(:user), event: "milestoned",
        title_is: "𠲖 title",
        ref: "a" * 256
      )

      detail = IssueEventDetail.find_by(id: event.issue_event_detail.id)

      assert_equal "a" * 255, T.must(detail).ref
    end

    test "ref with over 255 characters and emoji is truncated" do
      event = create(:issue_event,
        actor: create(:user), event: "milestoned",
        title_is: "𠲖 title",
        ref: "a" * 256 + "🐹" + "aaaa"
      )

      detail = IssueEventDetail.find_by(id: event.issue_event_detail.id)

      assert_equal "a" * 255, T.must(detail).ref
    end

    test "ref with over 255 characters with emoji before 255 is truncated" do
      event = create(:issue_event,
        actor: create(:user), event: "milestoned",
        title_is: "𠲖 title",
        ref: "a" * 100 + "🐹" + "a" * 155
      )

      detail = IssueEventDetail.find_by(id: event.issue_event_detail.id)

      assert_equal "a" * 100, T.must(detail).ref
    end
  end

  context "encoding attributes that may contain unicode characters" do
    test "forces encoding for #milestone_title, #title_is and #title_was" do
      event = create(:issue_event,
        actor: create(:user), event: "milestoned",
        milestone_title: "milestone title".b,
        title_is: "some title".b,
        title_was: "some title".b,
        message: "some title".b
      )

      assert_equal Encoding::UTF_8, event.milestone_title.encoding
      assert_equal Encoding::UTF_8, event.title_is.encoding
      assert_equal Encoding::UTF_8, event.title_was.encoding
      assert_equal Encoding::UTF_8, event.message.encoding
    end
  end

  context "validations" do
    test "disallows milestone_title longer than varbinary 1024" do
      oversize_title = SecureRandom.base64(IssueEventDetail::UTF8_BYTESIZE_LIMIT + 1)

      event = IssueEvent.new(
        actor: create(:user), event: "milestoned",
        milestone_title: oversize_title
      )

      refute_predicate event, :valid?
      assert_match /is too long/, event.issue_event_detail.errors.messages[:milestone_title].first
    end

    test "disallows title_is and title_was longer than varbinary 1024" do
      oversize_title = SecureRandom.base64(IssueEventDetail::UTF8_BYTESIZE_LIMIT + 1)

      event = IssueEvent.new(
        actor: create(:user), event: "milestoned",
        title_is: oversize_title,
        title_was: oversize_title
      )

      refute_predicate event, :valid?
      assert_match /is too long/, event.issue_event_detail.errors.messages[:title_is].first
      assert_match /is too long/, event.issue_event_detail.errors.messages[:title_was].first
    end

    test "disallows message longer than varbinary 1024" do
      oversize_title = SecureRandom.base64(IssueEventDetail::UTF8_BYTESIZE_LIMIT + 1)

      event = IssueEvent.new(
        actor: create(:user), event: "milestoned",
        message: oversize_title
      )

      refute_predicate event, :valid?
      assert_match /is too long/, event.issue_event_detail.errors.messages[:message].first
    end
  end

  context "#subject" do
    test "finds subject even when subject_type is nil" do
      user = create(:user)
      issue_event = create(:issue_event, subject_id: user.id)

      clean_issue_event = IssueEvent.find(issue_event.id)
      refute clean_issue_event.subject_type
      assert_equal user, clean_issue_event.subject
    end

    test "returns nil for subject if subject does not exist" do
      issue_event = create(:issue_event, subject_id: 0)
      assert_nil issue_event.subject
    end
  end

  [:milestone_title, :title_is, :title_was, :message, :column_name, :previous_column_name, :label_name].each do |field|
    test "supports emoji for #{field}" do
      issue_event = create(:issue_event, field => "we ❤️ emojis")

      assert_multibyte_tracked_changes(issue_event.issue_event_detail, field)
    end
  end

  test "sets `repository_id` from issue_event" do
    issue_event = create(:issue_event)
    detail = issue_event.issue_event_detail

    refute_nil detail.repository_id
    assert_equal detail.repository_id, issue_event.repository_id
  end

  context "attributes" do
    test "sets state_reason for issues when it is specified" do
      gerald = create(:user)

      issue = create(:issue, user: gerald)

      # Closing the issue considers state_reason attribute
      assert issue.close(gerald, attributes: { state_reason: :not_planned })
      issue_event = IssueEvent.find_by(issue_id: issue.id, event: "closed")
      detail = T.must(issue_event).issue_event_detail
      refute_nil detail[:state_reason]
      assert_equal true, detail.state_reason_not_planned?

      # Reopening the issue considers the state_reason attribute
      issue.open(gerald, { state_reason: :reopened })
      issue_event = IssueEvent.find_by(issue_id: issue.id, event: "reopened")
      detail = T.must(issue_event).issue_event_detail
      refute_nil detail[:state_reason]
      assert_equal true, detail.state_reason_reopened?

      # Closing the issue as completed does not consider state_reason
      assert issue.close(gerald)

      issue_event = IssueEvent.where(issue_id: issue.id, event: "closed").order(:id).offset(1).take!
      detail = issue_event.issue_event_detail
      assert_nil detail[:state_reason]
    end

    test "creates a closed event when the closing reason is specified" do
      gerald = create(:user)
      issue = create(:issue, user: gerald)

      assert issue.close(gerald, attributes: { state_reason: nil })
      assert_equal 1, IssueEvent.where(issue_id: issue.id, event: "closed").count

      assert issue.close(gerald, attributes: { state_reason: :not_planned })
      assert_equal 2, IssueEvent.where(issue_id: issue.id, event: "closed").count

      issue_event = IssueEvent.where(issue_id: issue.id, event: "closed").order(:id).offset(1).take!
      detail = issue_event.issue_event_detail
      assert_equal true, detail.state_reason_not_planned?
    end
  end

end
