# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class EmailJob < ApplicationJob
  retry_on_dirty_exit

  queue_as :email
  # Any EmailError raised with one of the following reason codes
  # will trigger an automated response to the User informing them
  # that GitHub failed to process their email.
  NOTIFIABLE_ERRORS = [:blank_body, :locked_issue, :must_verify_email, :disabled].freeze

  resolve_tenant_context do |mail|
    code = mail["reply_code"] || mail[:reply_code]
    next unless code

    signed_auth_token = GitHub::Email::Token.signed_auth_token_from_token(code)
    sender = GitHub::Email::Token.sender_from_signed_auth_token(signed_auth_token)
    target = GitHub::Email::Token.target_from_signed_auth_token(signed_auth_token, sender)
    next unless target

    list = target
    list = target.notifications_list if target.respond_to?(:notifications_list)

    Notifications::TenantContext.resolve_tenant(list)
  rescue GitHub::Email::Token::LegacyTokenError
    nil
  end

  # Represents an error in processing inbound email.
  class EmailError < StandardError
  end

  attr_reader :mail, :sender, :target, :creation, :error, :from_address
  # The result code of the email process - this defaults to "success", but will
  # be changed to an error_code if an EmailError is raised
  attr_reader :result

  # Helper for setting up a new instance of the job with the correct
  # mail hash from Astrotrain.  If you want to reply to a comment
  # as bob:
  #
  #   mail = EmailJob.mail_hash_for(@comment, @bob, :body => 'my reply')
  #   EmailJob.perform_now(mail)
  #
  sig do
    params(
      target: T.untyped,
      author: User,
      options: T::Hash[T.any(String, Symbol), T.untyped]
    ).returns(T::Hash[String, T.untyped])
  end
  def self.mail_hash_for(target, author, options = {})
    headers = { "message-id" => "<123>" }
    if custom_headers = options.delete(:headers)
      headers.update(custom_headers)
    end

    {
      "reply_code" => GitHub::Email::Token.target_token(target, author),
      "from"       => [{ "address" => author.email }],
      "headers"    => headers,
      "body"       => options.delete(:body).to_s,
      "html"       => options.delete(:html).to_s,
    }.update(options.stringify_keys)
  end

  # Public: handle the case where we can't process
  # an inbound email for some reason.
  #
  # Notifies the User of the processing error
  # when appropriate.
  #
  # Raises EmailJob::EmailError
  # Returns nil
  sig { params(error_code: Symbol).void }
  def email_error!(error_code)
    @result = error_code
    GitHub.dogstats.increment "email_reply", tags: ["error:#{error_code}"]

    raise EmailError, error_code
  end

  sig { void }
  def load_sender_and_target
    code = @mail["reply_code"] || email_error!(:no_reply_code)
    @mail["from"].present? || email_error!(:no_from_address)
    @from_address = @mail["from"].first["address"]

    begin
      signed_auth_token = GitHub::Email::Token.signed_auth_token_from_token(code)
      @sender = GitHub::Email::Token.sender_from_signed_auth_token(signed_auth_token) || email_error!(
        "token_invalid_#{signed_auth_token&.reason || "unknown_reason"}".to_sym
      )
      @target = GitHub::Email::Token.target_from_signed_auth_token(signed_auth_token, @sender) || email_error!(:no_target)
    rescue GitHub::Email::Token::LegacyTokenError
      AccountMailer.legacy_reply_token_bounce(self).deliver_now
      email_error!(:legacy_token)
    end

    check_for_ignoring(@sender, @target)
  end

  def check_for_ignoring(sender, target)
    target_user_ids = target_author_ids(target)

    if sender.blocked_by?(*target_user_ids)
      email_error!(:ignored_by_targets)
    elsif sender.blocking?(*target_user_ids)
      email_error!(:ignoring_targets)
    end
  end

  sig { params(target: T.untyped).returns(T::Array[Integer]) }
  def target_author_ids(target)
    user_ids = []

    if target.respond_to?(:repository)
      user_ids << target.repository.try(:owner_id)
    end

    if target.respond_to?(:user_id)
      user_ids << target.user_id
    end

    user_ids.compact!
    user_ids.uniq!

    user_ids
  end

  sig { void }
  def log_result_in_syslog
    message = {}
    if @error
      message[:error] = @error.to_s
    else
      message.update \
        saved_at: Time.now.utc.iso8601,
        url: url_of(@creation)
    end
    if message[:error]
      GitHub.logger.error("Error processing email job", {
        "code.namespace" => self.class.name,
        "exception.message" => message,
        "gh.notifications.message_id" => @mail["headers"]["message-id"],
        "gh.notifications.author.id" => @sender&.id
      })
    else
      GitHub.logger.info("Email job processed", {
        "code.namespace" => self.class.name,
        "gh.notifications.message_id" => @mail["headers"]["message-id"],
        "gh.notifications.author.id" => @sender&.id,
        "gh.notifications.result" => result.to_s
      })
    end
  end

  AUTOREPLY_HEADERS = %w(precedence x-auto-response-suppress)
  # Internal: Return the first Auto-reply header for the email if found
  # Otherwise returns nil
  def autoreply_header
    self.class.autoreply_header(@mail["headers"])
  end
  alias_method :autoreply_value, :autoreply_header

  def self.autoreply_header(headers)
    AUTOREPLY_HEADERS.detect do |an_autoreply_header|
      headers[an_autoreply_header].present?
    end
  end

  sig { params(item: T.nilable(ActiveRecord::Base)).returns(T.nilable(String)) }
  def url_of(item)
    case item
    when CommitComment
      "%s/%s/commit/%s#commitcomment-%d" % [
        GitHub.url,
        item.repository&.name_with_owner,
        item.commit.oid, item.id]
    when IssueComment
      "%s#issuecomment-%d" % [
        item.issue&.permalink, item.id]
    when PullRequestReviewComment
      "%s#issuecomment-%d" % [
        item.pull_request&.permalink, item.id]
    end
  end

  # Public: Returns the Message-Id header of this email.
  #
  # Returns a String or nil.
  sig { returns T.nilable(String) }
  def message_id
    @mail["headers"]["message-id"]
  end

  # Public: Returns the Subject header of this email.
  def subject
    @mail["subject"]
  end
end
