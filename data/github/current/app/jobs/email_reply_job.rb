# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class EmailReplyJob < EmailJob
  # Main mail reply processing job. Incoming mail is processed by the
  # mail-replies project running on the smtp* machines:
  #
  # https://github.com/github/mail-replies
  #
  # Each mail is converted to a simple hash payload and enqueued for this job.
  # The payload includes the following information:
  #
  #   'from'       => address list array (see below)
  #   'to'         => address list array
  #   'cc'         => address list array
  #   'subject'    => string message subject
  #   'body'       => string plain text body of the message
  #   'html'       => string html body of the message (if present)
  #   'reply_code' => string mail target code that determines what github
  #                   object the message should be applied to.
  #   'headers'    => hash of all mail headers with downcase string keys
  #
  # The address list array is an array of hashes. Each hash includes
  # 'address' and 'name' keys:
  #
  #   [{'address' => string email, 'name' => string name}, ...]
  #
  # The 'html' and 'body' keys store different MIME parts of the message. If
  # the message is sent with multipart encoding, both may be present.
  # Otherwise the messages content-type is used to determine whether the
  # message is text/plain or text/html.
  #
  # See also the EmailJob base class for instance variables and
  # setup performed when a new job is created.

  include GitHub::Tracing

  trace_method :load_sender_and_target
  trace_method :process_reply

  queue_as :email_reply

  retry_on_dirty_exit

  retry_on StandardError

  DATABASE_UNAVAILABLE_EXCEPTIONS = [
      Freno::Throttler::Error,
      *Resiliency::Response::UnavailableExceptions
    ]

  retry_on *DATABASE_UNAVAILABLE_EXCEPTIONS, wait: :polynomially_longer, attempts: 20

  discard_on ActiveRecord::RecordInvalid do |_job, error|
    raise error
  end

  attr_reader :mail, :sender, :target, :creation, :error, :from_address

  def perform(mail = nil, options = {})
    GitHub.dogstats.increment "email_reply"
    return if mail.blank?

    @mail = mail.deep_stringify_keys
    @mail["headers"] ||= {}
    @result = "success"

    if key = autoreply_value
      email_error!(:autoreply)
    end

    load_sender_and_target
    process_reply

    # return an instance for checking processing results in tests
    self
  rescue EmailError => err
    @error = err # sent to syslog, see log_result_in_syslog
    self
  rescue Object => err # rubocop:todo Lint/GenericRescue
    @error = err
    raise
  ensure
    log_result_in_syslog
  end

  def process_reply
    creation_method_name =
      if @target.respond_to?(:email_reply_creation_method)
        @target.email_reply_creation_method
      else
        "reply_to_#{@target.class.name.underscore}"
      end

    respond_to?(creation_method_name) || email_error!(:invalid_reply)

    if @target.respond_to?(:repository)
      if @target.repository
        # These are handled by the content authorizer. Remove when
        # proper internal error codes are implemented.
        if !@target.repository.pullable_by?(@sender)
          email_error!(:denied_access)
        end

        if @target.repository.access.disabled?
          email_error!(:disabled)
        end
      else
        email_error!(:repository_deleted)
      end
    end

    if @target.try(:locked?) && @target.locked_for?(@sender)
      email_error!(:locked_issue)
    end

    authorize_user!
    authorize_content!

    @body = sanitize_body(@mail)

    if blank_reply?(@body)
      email_error!(:blank_body)
    end

    is_duplicate = with_write do
      duplicate_check = Notifications::DuplicateContentCheck.new(@sender.id)
      dup = duplicate_check.duplicate?(@body)
      duplicate_check.save @body
      dup
    end

    if is_duplicate
      email_error!(:duplicate_body)
    end

    @creation = with_write do
      send(creation_method_name)
    end
    return unless @creation&.is_a?(Notifications::SubscribableThread)

    thread_rollup_response = GitHub.newsies.web.find_rollup_summary_by_thread(
      @creation.notifications_list,
      @creation.notifications_thread)
    return unless thread_rollup_response&.success? && thread_rollup_response.value

    Newsies::NotificationEntry.throttle do
      with_write do
        GitHub.newsies.web.mark_summary_read(@sender, thread_rollup_response.value)
      end
    end
  end

  def reply_to_message
    @target.reply_from_email from: @sender, body: @body
  end

  def reply_to_commit_comment
    options = { user: @sender, body: @body, formatter: "email" }
    [:position, :path, :commit_id, :line, :repository_id].each do |field|
      options[field] = @target.send(field)
    end
    CommitComment.create! options
  end

  def reply_to_commit_mention
    CommitComment.create!(
      repository_id: @target.repo_id,
      commit_id: @target.commit_id,
      formatter: "email",
      user: @sender,
      body: @body,
    )
  end

  def reply_to_team_discussion(discussion: @target)
    mutation = Platform.execute(
      team_discussion_comment_create_mutation,
      target: :internal,
      variables: {
        "input" => {
          "discussionId" => discussion.global_relay_id,
          "body" => @body,
          "formatter" => "EMAIL",
        },
      },
      context: { viewer: @sender })

    if mutation.errors.any?
      email_error!(:denied_access)
    end

    _, comment_id = Platform::Helpers::NodeIdentification.from_global_id(
      mutation.data["createTeamDiscussionComment"]["teamDiscussionComment"]["id"])

    DiscussionPostReply.find(comment_id)
  end

  def reply_to_team_discussion_comment
    reply_to_team_discussion(discussion: @target.discussion_post)
  end

  def reply_to_issue
    IssueComment.create!( # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      issue_id: @target.id,
      repository_id: @target.repository_id,
      user_id: @sender.id,
      body: @body,
      formatter: "email"
    )
  end

  def reply_to_pull_request_review_comment
    comment = @target.pull_request_review_thread.build_reply(pull_request_review: @target.pull_request_review, user: @sender, body: @body)
    comment.formatter = "email"
    comment.submit!

    GitHub.dogstats.increment("pull_request_review_comment", tags: ["action:reply_to_pull_request_review_comment"])
    comment
  end

  def reply_to_gist
    @target.comments.create! user_id: @sender.id, body: @body,
      formatter: "email"
  end

  def reply_to_repository_advisory
    @target.comments.create!(user: @sender, body: @body, formatter: "email")
  end

  def reply_to_discussion
    @target.comments.create!(user: @sender, body: @body, formatter: "email")
  end

  def sanitize_body(mail)
    if (body = mail["body"].dup).blank?
      body = Nokogiri::HTML(mail["html"].to_s).inner_text
      body.rstrip!
    end

    # We are running essentially the same logic here as we do for HTML content
    # in HTML::Pipeline::EmailReplyFilter when :hide_quoted_email_addresses is
    # enabled. It would be nicer to just do it in the filter, however we also
    # want to be sure we don't add PII data from the raw content body in the
    # database. And the filter would only filter it out when presenting HTML
    # to the user but not when storing the raw body in the database.
    body.gsub!(::HTML::Pipeline::EmailReplyFilter::EMAIL_REGEX, ::HTML::Pipeline::EmailReplyFilter::HIDDEN_EMAIL_PATTERN)

    # Validation will fail and the user won't know if length is 65535
    # characters or more, so truncate the rare emails that are that long
    body[0..65530]
  end

  def blank_reply?(body)
    reply = EmailReplyParser.read(body.dup)
    reply.fragments.none? do |fragment|
      !fragment.hidden? && fragment.to_s.strip.size > 0
    end
  end

  private

  def authorize_user!
    # We don't need to do EMU check on GHE environments
    return if GitHub.enterprise?

    with_read do
      return unless GitHub.multi_tenant_enterprise? || @sender.is_enterprise_managed?

      email_error!(:denied_emu_access) unless @sender.enterprise_managed_business == target_business
    end
  end

  def authorize_content!
    target_type = @target.class.name.underscore
    return unless ContentAuthorizer.can_authorize?(target_type)

    data = {}.tap do |attrs|
      attrs[:repo]  = @target.repository if @target.respond_to?(:repository)
      attrs[:issue] = @target.issue if @target.respond_to?(:issue)
      attrs[:discussion] = @target if @target.is_a?(Discussion)
    end

    authorization = ContentAuthorizer.authorize(@sender, target_type, :create, data)

    if authorization.failed?
      if authorization.has_email_verification_error?
        email_error!(:must_verify_email)
      else
        email_error!(:content_authorization_error)
      end
    end
  end

  # Returns a parsed GraphQL query used to create a team discussion comment.
  def team_discussion_comment_create_mutation
    @team_discussion_comment_create_mutation ||= GraphQL.parse <<-'GRAPHQL'
          mutation($input: CreateTeamDiscussionCommentInput!) {
            createTeamDiscussionComment(input: $input)  {
              teamDiscussionComment {
                id
              }
            }
          }
    GRAPHQL
  end

  # Return the Business associated to the target to perform EMU check
  # when applicable
  def target_business
    case @target
    when ->(target) { target.respond_to?(:repository) }
      if @sender&.feature_enabled?(:email_reply_proxima_private_reply)
        @target.repository&.enterprise_managed_business
      else
        @target.repository&.business
      end
    when DiscussionPost
      @target.team&.organization&.business
    when Gist
      @target.owner&.enterprise_managed_business
    else
      nil
    end
  end
end
