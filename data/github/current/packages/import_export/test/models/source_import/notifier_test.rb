# typed: false
# frozen_string_literal: true

require "test_helper"

class SourceImportNotifierTest < GitHub::TestCase
  fixtures do
    @organization = create(:organization)
    @repository = create(:repository, owner: @organization)
    @user = create(:user, login: "user")
    @status = "succeeded"
    @failure_reason = ""
    @error_details = []
  end

  def source_import_notifier(
    repository: @repository,
    user: @user,
    status: @status,
    failure_reason: @failure_reason,
    error_details: @error_details,
    notify_by_webhook: true,
    notify_by_mail: true
  )
    SourceImport::Notifier.new(
      repository:        repository,
      user:              user,
      status:            status,
      failure_reason:    failure_reason,
      error_details:     error_details,
      notify_by_webhook: notify_by_webhook,
      notify_by_mail:    notify_by_mail,
    )
  end

  context "#repository" do
    test "returns repository" do
      assert_equal(source_import_notifier.repository, @repository)
    end
  end

  context "#user" do
    test "returns user" do
      assert_equal(source_import_notifier.user, @user)
    end
  end

  context "#status" do
    test "returns status" do
      assert_equal(source_import_notifier.user, @user)
    end
  end

  context "#failure_reason" do
    test "returns failure_reason" do
      assert_equal(source_import_notifier.failure_reason, @failure_reason)
    end
  end

  context "#message_type" do
    test "returns message_type from status" do
      assert_equal(
        source_import_notifier.message_type, SourceImport::Notifier::STATUS_MESSAGE_TYPE_MAPPINGS[@status]
      )
    end
  end

  context "#completed_status" do
    test "returns success when status is succeeded" do
      assert_equal(source_import_notifier.completed_status, "success")
    end

    test "returns failure when status is failed" do
      notifier = source_import_notifier(status: "failed")

      assert_equal(notifier.completed_status, "failure")
    end

    test "returns failure when status is failed_validation" do
      notifier = source_import_notifier(status: "failed_validation")

      assert_equal(notifier.completed_status, "failure")
    end
  end

  context "#notify_if_complete" do
    test "calls notify and returns true if completed_status is truthy" do
      notifier = source_import_notifier

      notifier.expects(:notify)
      assert(notifier.notify_if_complete)
    end

    test "doesn't call notify and returns false if completed_status is falsey" do
      notifier = source_import_notifier
      notifier.expects(:completed_status).returns(nil)

      def notifier.notify
        raise(NoMethodError, "This method should not be called.")
      end

      refute(notifier.notify_if_complete)
    end
  end

  context "#validate_message_type" do
    test "does not raise UnsupportedMessageType if completed_status is truthy" do
      source_import_notifier.send(:validate_message_type)
    end

    test "raises UnsupportedMessageType if completed_status is falsey" do
      notifier = source_import_notifier
      notifier.expects(:completed_status).returns(nil)

      assert_raises SourceImport::Notifier::UnsupportedMessageType do
        notifier.send(:validate_message_type)
      end
    end
  end

  context "#notify" do
    test "calls send_mail and enqueue_hook" do
      notifier = source_import_notifier

      notifier.expects(:send_mail)
      notifier.expects(:enqueue_hook)

      notifier.send(:notify)
    end

    test "doesn't call send_mail if notify_by_mail is false" do
      notifier = source_import_notifier(notify_by_mail: false)

      notifier.expects(:send_mail).never
      notifier.expects(:enqueue_hook)

      notifier.send(:notify)
    end

    test "doesn't call enqueue_hook if notify_by_webhook is false" do
      notifier = source_import_notifier(notify_by_webhook: false)

      notifier.expects(:send_mail)
      notifier.expects(:enqueue_hook).never

      notifier.send(:notify)
    end
  end

  context "#send_mail" do
    test "calls SourceImportMailer with correct arguments" do
      notifier = source_import_notifier

      mail_message = mock("mail_message")
      mail_message.expects(:deliver_later)

      SourceImportMailer.expects(
        :import_success,
      ).with(
        repository:     notifier.repository,
        user:           notifier.user,
        status:         notifier.status,
        failure_reason: notifier.failure_reason,
        error_details:  notifier.error_details,
      ).returns(
        mail_message,
      )

      notifier.send(:send_mail)
    end
  end

  context "#enqueue_hook" do
    test "calls GitHub.instrument with correct arguments" do
      notifier = source_import_notifier

      GitHub.expects(
        :instrument,
      ).with(
        "repository_import.import",
        status:   notifier.completed_status,
        repo_id:  notifier.repository.id,
        actor_id: notifier.user.id,
      )

      notifier.send(:enqueue_hook)
    end
  end
end
