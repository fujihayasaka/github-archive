# typed: true
# frozen_string_literal: true

class EmailUnsubscribeJob < EmailJob
  retry_on_dirty_exit

  queue_as :email_unsubscribe

  def perform(mail = nil, options = {})
    return if mail.blank?

    @mail = mail.deep_stringify_keys
    @mail["headers"] ||= {}
    @result = "success"
    load_sender_and_target

    unsub_method_name = "unsub_from_#{@target.class.name.underscore}"

    respond_to?(unsub_method_name) || raise(EmailError, :unable_to_reply)

    send(unsub_method_name)

    # return an instance for checking processing results in tests
    self
  rescue EmailError => err
    @error = err # see log_result_in_syslog
    self
  rescue Object => err # rubocop:todo Lint/GenericRescue
    @error = err
    raise
  ensure
    log_result_in_syslog
  end

  def unsub_from_commit_comment
    Newsies::ThreadSubscription.throttle_writes do
      Notifications::Subscriptions.unsubscribe_from_thread(@sender, @target)
    end
  end

  def unsub_from_issue(issue = @target)
    Newsies::ThreadSubscription.throttle_writes do
      Notifications::Subscriptions.unsubscribe_from_thread(@sender, issue)
    end
  end

  def unsub_from_pull_request_review_comment
    unsub_from_issue @target.pull_request.issue
  end
end
