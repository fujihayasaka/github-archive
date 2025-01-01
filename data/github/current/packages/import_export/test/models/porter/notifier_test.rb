# typed: false
# frozen_string_literal: true

require "test_helper"

class PorterNotifierTest < GitHub::TestCase
  fixtures do
    @organization = create(:organization)
    @repository = create(:repository, owner: @organization)
    @user = create(:user, login: "user")
    @porter_data = {
      "message_type"  => "import_success",
      "authors_found" => false,
    }
  end

  def porter_notifier(
    porter_data: @porter_data,
    repository: @repository,
    user: @user,
    notify_by_webhook: true,
    notify_by_mail: true
  )
    Porter::Notifier.new(
      porter_data: porter_data,
      repository:  repository,
      user:        user,
      notify_by_webhook: notify_by_webhook,
      notify_by_mail: notify_by_mail,
    )
  end

  context "#porter_data" do
    test "returns porter_data" do
      assert_equal(porter_notifier.porter_data, @porter_data)
    end
  end

  context "#repository" do
    test "returns repository" do
      assert_equal(porter_notifier.repository, @repository)
    end
  end

  context "#user" do
    test "returns user" do
      assert_equal(porter_notifier.user, @user)
    end
  end

  context "#message_type" do
    test "returns message_type from porter_data" do
      assert_equal(
        porter_notifier.message_type, @porter_data["message_type"].to_s
      )
    end
  end

  context "#completed_status" do
    test "returns success when message_type is import_success" do
      assert_equal(porter_notifier.completed_status, "success")
    end

    test "returns failure when message_type is import_failure" do
      porter_data = @porter_data.merge("message_type" => "import_failure")
      notifier = porter_notifier(porter_data: porter_data)

      assert_equal(notifier.completed_status, "failure")
    end

    test "returns cancelled when message_type is import_cancelled" do
      porter_data = @porter_data.merge("message_type" => "import_cancelled")
      notifier = porter_notifier(porter_data: porter_data)

      assert_equal(notifier.completed_status, "cancelled")
    end

    test "returns nil when message_type is not a completed status" do
      porter_data = @porter_data.merge("message_type" => "garbage")
      notifier = porter_notifier(porter_data: porter_data)

      assert_nil(notifier.completed_status, nil)
    end
  end

  context "#authors found" do
    test "returns authors_found from porter_data" do
      assert_equal(porter_notifier.authors_found, @porter_data["authors_found"])
    end
  end

  context "#notify_if_complete" do
    test "calls notify and returns true if completed_status is truthy" do
      notifier = porter_notifier

      notifier.expects(:notify)
      assert(notifier.notify_if_complete)
    end

    test "doesn't call notify and returns false if completed_status is falsey" do
      notifier = porter_notifier
      notifier.expects(:completed_status).returns(nil)

      def notifier.notify
        raise(NoMethodError, "This method should not be called.")
      end

      refute(notifier.notify_if_complete)
    end
  end

  context "#validate_message_type" do
    test "does not raise UnsupportedMessageType if completed_status is truthy" do
      porter_notifier.send(:validate_message_type)
    end

    test "raises UnsupportedMessageType if completed_status is falsey" do
      notifier = porter_notifier
      notifier.expects(:completed_status).returns(nil)

      assert_raises Porter::Notifier::UnsupportedMessageType do
        notifier.send(:validate_message_type)
      end
    end
  end

  context "#notify" do
    test "calls send_mail and enqueue_hook" do
      notifier = porter_notifier

      notifier.expects(:send_mail)
      notifier.expects(:enqueue_hook)

      notifier.send(:notify)
    end

    test "doesn't call send_mail if notify_by_mail is false" do
      notifier = porter_notifier(notify_by_mail: false)

      notifier.expects(:send_mail).never
      notifier.expects(:enqueue_hook)

      notifier.send(:notify)
    end

    test "doesn't call enqueue_hook if notify_by_webhook is false" do
      notifier = porter_notifier(notify_by_webhook: false)

      notifier.expects(:send_mail)
      notifier.expects(:enqueue_hook).never

      notifier.send(:notify)
    end
  end

  context "#send_mail" do
    test "calls PorterMailer with correct arguments" do
      notifier = porter_notifier

      mail_message = mock("mail_message")
      mail_message.expects(:deliver_later)

      PorterMailer.expects(
        :import_success,
      ).with(
        repository:    notifier.repository,
        current_user:  notifier.user,
        authors_found: notifier.authors_found,
      ).returns(
        mail_message,
      )

      notifier.send(:send_mail)
    end
  end

  context "#enqueue_hook" do
    test "calls GitHub.instrument with correct arguments" do
      notifier = porter_notifier

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
