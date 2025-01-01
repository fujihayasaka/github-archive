# typed: true
# frozen_string_literal: true


# Public: Stores Thread Summaries in ActiveRecord.
# Newsies works with a broad definition of what a List or Thread is.
#
# On the main GitHub.com site:
# * Lists: Repository, Team, User
# * Threads: Issue, Commit, RepositoryInvitation, DiscussionPost, Vulnerability
# * Comments: IssueComment, CommitComment, PullRequestReviewComment, PullRequestReview, DiscussionPostReply
#
# Note that this list might not complete as other models could have been added over time.
#
# PullRequests are treated as Issues, because that's really the owner of the
# Thread.  Issues will summarize Issue and Pull Request comments.
# CommitComments will be summarized in the Commit thread, since there's no simple
# way to scan for Pull Requests relating to a single commit.
#
class NotificationSummary < ApplicationRecord::Domain::NotificationsSummaries
  include T::Sig
  include T::Helpers
  include GitHub::IFlipperActor
  include GitHub::VexiActor
  include Coders::CodableColumn

  class Error < StandardError; end
  class SaveError < Error; end

  class LoadError < Error
    def initialize(summary, exception)
      @summary = summary
      @exception = exception
    end

    def backtrace
      @exception.backtrace
    end

    def message
      "Unable to read Summary data for %s: #{@exception.class}" %
        %(#<NotificationSummary id: #{@summary.id}>)
    end

    alias to_s message
  end

  ITEM_KEY_SEPARATOR = ":"

  before_save :trim_item_keys!
  before_save :trim_item_body_html!
  after_create :log_summary_creation
  after_update :log_summary_update

  serialize_with_coder :raw_data, Coders::NotificationSummaryCoder

  attr_accessor :unread, :mentioned, :important
  attr_writer :item_limit

  class << self
    attr_accessor :item_limit
    attr_writer :comment_body_size_threshold
  end
  self.item_limit = 10

  # Private: Summarizes the given comment in the thread.  Threads should have
  # a single summary, no matter how many comments there are.
  #
  # NOTE: This method will always update the record in the database, even if it exists.
  #
  # Use Newsies::Web::find_or_create_rollup_summary_from_list_thread_comment
  #
  # list    - Usually a Repository.
  # thread  - An Issue, Commit, or RepositoryInvitation.
  # comment - Some *Comment instance.
  #
  # Returns a NotificationSummary.
  def self.fetch_and_update!(list, thread, comment)
    retries = 0
    begin
      summary = by_thread(list, thread) || new(list: list, thread: thread)
      summary.summarize!(comment)
    rescue SaveError
      summary.rebuild_summary
      if retries.zero?
        retries += 1
        retry
      else
        raise
      end
    end
  end

  # Private: Finds an existing Summary for the given list and thread.
  #
  # Use Newsies::Web::find_rollup_summary_by_thread
  #
  # list    - Usually a Repository.
  # thread  - An Issue or Commit.
  #
  # Returns a NotificationSummary, or nil if none is found.
  def self.by_thread(list, thread)
    list = Newsies::List.to_object(list)
    thread = Newsies::Thread.to_object(thread)
    find_by(list_type: list.type, list_id: list.id, thread_key: thread.key)
  end

  def self.comment_body_size_threshold
    @comment_body_size_threshold ||= 5.kilobytes
  end

  def list
    if @list.nil?
      @list = list_type.constantize.find_by_id(list_id)
    end

    (@list ||= false) || nil
  end

  def list=(list)
    reset_lists

    if list
      @newsies_list = Newsies::List.to_object(list)
      write_attribute :list_id, newsies_list.id
      write_attribute :list_type, newsies_list.type
    else
      write_attribute :list_id, nil
      write_attribute :list_type, nil
    end
  end

  def list_owner_id
    return list.id if list.is_a?(User) || list.is_a?(Organization)

    list.try(:owner_id) || list.try(:organization_id)
  end

  def thread_author_id
    thread.try(:notifications_author).try(:id)
  end

  # Public: Loads the Thread for this Summary.  This is very much like an
  # ActiveRecord polymorphic join, except we get the added challenge of
  # linking to a Commit too.  There are 2 columns that make up the thread:
  #
  # thread_type - The String class name.
  # thread_id   - The unique String ID of the record -- Either a DB ID or a
  #               commit SHA.
  #
  # If the thread_type is an ActiveRecord class, we find the thread through
  # ActiveRecord.  Otherwise, we assume it's a commit, and find it through
  # the Repository Walker.
  #
  # Returns a Thread object (Issue, Gist, Commit).
  def thread
    if @thread.nil?
      if thread_key
        case newsies_thread.type
        when "Grit::Commit"
          @thread = list.commits.find(newsies_thread.id) if list
        when "DiscussionPost"
          # Typically, we would handle this in the `else` case, but doing so generates an access
          # exception. Since we can't easily get around the fact that the caller (Newsies) uses
          # ActiveRecord, and we've otherwise achieved GraphQL purity with DiscussionPost objects,
          # treat this as a known one-off.
          @thread = DiscussionPost.find_by(id: newsies_thread.id.to_i)
        else
          model = newsies_thread.type.constantize
          @thread = model.find_by_id(newsies_thread.id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        end
      end
    end

    (@thread ||= false) || nil
  end

  def thread=(thread)
    if thread
      @newsies_thread = Newsies::Thread.to_object(thread, list: newsies_list)
      @thread = thread
      self.thread_key = @newsies_thread.key
    else
      self.thread_key = nil
    end

    thread
  end

  def thread_key=(new_thread_key)
    reset_threads
    super
  end

  # Public: Publishes marked as read message to associated thread.
  #
  # user - User that read the thread.
  #
  # Returns true if delivered, false if not.
  def sync_thread_read_state(user)
    # No need to look up commits at this time
    return false if newsies_thread.type == "Grit::Commit"

    return false unless thread && thread.respond_to?(:sync_thread_read_state)

    thread.sync_thread_read_state(user)
  end

  # Public: Publishes notification event (read/unread, archive/unarchive, save/unsave) message to associated thread.
  #
  # user - User that read the thread.
  #
  # Returns true if delivered, false if not.
  def sync_notifications_changed(user)
    # No need to look up commits at this time
    return false if newsies_thread.type == "Grit::Commit"

    return false unless thread && thread.respond_to?(:sync_notifications_changed)

    thread.sync_notifications_changed(user)
  end

  # Public: Gets the unread status for a Summary.  This information is not
  # stored with the Summary, but the Index.  So, it's usually false, unless
  # you're getting it from Newsies::WebHandler#summaries.
  #
  # Returns a Boolean.
  def unread?
    !!@unread
  end

  def mentioned?
    !!@mentioned
  end

  def important?
    !!@important
  end

  # Public: Gets the summarized Hash of the given comment.
  #
  # comment - An ActiveRecord comment instance.
  #
  # Returns a Hash.
  def item(comment)
    items[item_key(comment)]
  end

  # Public: Sets the summarized hash of the given comment.
  #
  # comment - An ActiveRecord comment instance.
  # hash    - The summarized hash of the comment.
  #
  # Returns nothing.
  def set_item(comment, hash)
    items[item_key(comment)] = hash
  end

  # Public: Gets the String key of a summarized comment in the `#items` Hash.
  #
  # comment - An ActiveRecord comment instance.
  #
  # Returns a String Hash key.
  def item_key(comment)
    Newsies::Comment.to_key(comment, separator: ITEM_KEY_SEPARATOR)
  end

  def delete_item(comment)
    delete_item_by_key(item_key(comment))
  end

  def to_summary_hash
    raw_data.to_h.merge(
      id: id.to_s,
      updated_at: updated_at,
      list: {
        id: list_id.to_s,
        type: list_type,
      },
      thread: {
        id: newsies_thread.id,
        type: newsies_thread.type,
      }
    )
  rescue Zlib::Error => err
    GitHub.dogstats.increment("notification_summary", tags: ["action:gzip_load"])
    raise LoadError.new(self, err)
  end

  # Public
  def rebuild_summary(save_record: true)
    self.raw_data = nil
    case thread
    when Gist
      summarize_gist_thread(thread)
    when CheckSuite
      comment = CheckSuiteEventNotification.new(thread)
      summarize(comment)
    when Actions::WorkflowRun
      comments = thread.latest_check_runs.lazy.filter_map do |check_run|
        check_run.gate_requests.find do |gate_request|
          gate_request.gate.type == "manual_approval"
        end
      end
      comment = comments.first
      if comment
        summarize_comment(comment)
      else
        summarize_workflow_run(thread)
      end
    when SecurityAdvisory
      alert = thread.vulnerability_alerting_events.where(reason: :on_process_alerts).last
      alert ||= Struct.new(:id, :vulnerability, :created_at).new(thread.id, thread, thread.created_at)
      comment = VulnerabilityAlertingEvent::SecurityAdvisoryNotification.new(list, alert)
      summarize(comment)
    when RepositoryDependabotAlertsThread
      alert = VulnerabilityAlertingEvent.where.not(reason: :on_process_alerts).where(repository_id: list.id).last
      alert ||= Struct.new(:id, :vulnerability, :created_at).new(thread.id, thread, Time.now)
      comment = VulnerabilityAlertingEvent::VulnerableRepositoryNotification.new(list, alert)
      summarize(comment)
    when RepositoryVulnerabilityAlert
      summarize_repository_vulnerability_alert(thread)
    when Issue
      summarize(thread)
      summarize_issue_thread thread, thread.pull_request
    when ::Commit
      summarize(thread)
      summarize_commit_thread thread.repository, thread.sha
    when ::RepositoryInvitation
      summarize(thread)
      summarize_repository_invitation thread
    when MemexProject
      summarize(thread.latest_status_update)
    else
      summarize(thread)
    end
    save! if save_record
  end

  # Internal: Summarizes the Thread with the new Comment, and saves it
  #
  # comment - Some *Comment instance.
  #
  # Returns this NotificationSummary instance.  If the List/Thread has already been
  # summarized, then return that instead.
  def summarize!(comment)
    summarize(comment)
    save!
    self
  rescue ActiveRecord::RecordNotUnique
    self.class.by_thread(list, thread) || raise
  end

  # Internal: Summarizes the Thread with the new Comment.  See the
  # #summarize_* methods to see how different Comment objects are handled.
  #
  # comment - Some *Comment instance.
  #
  # Returns nothing.
  def summarize(comment)
    return unless comment

    self.items ||= {}
    self.authors ||= {}

    case comment
    when AdvisoryCredit
      summarize_advisory_credit(comment)
    when Issue
      summarize_issues(comment)
    when IssueComment
      summarize_issue_thread(comment.issue) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    when IssueEventNotification
      summarize_issues(comment.issue)
      summarize_standard_comments(comment)
    when PullRequestReview
      pull = comment.pull_request
      summarize_issue_thread(pull.issue, pull) if pull&.issue
      summarize_pull_request_review(comment)
    when PullRequestReviewComment
      pull = comment.pull_request
      summarize_issue_thread(pull.issue, pull) if pull&.issue
    when CommitComment, CommitMention
      summarize_commit_thread(comment.repository, comment.commit_id)
    when ::Commit
      summarize_commit_thread(comment.repository, comment.sha)
    when GistComment
      summarize_gist_thread(comment.gist)
    when Release
      summarize_release(comment)
    when ::RepositoryInvitation
      summarize_repository_invitation(comment)
    when PullRequestPushNotification
      summarize_pull_request_push_notification(comment)
    when DiscussionPost
      summarize_discussion_post(comment)
    when DiscussionPostReply
      summarize_discussion_post_thread(comment)
    when RepositoryVulnerabilityAlert::WebNotification
      summarize_repository_vulnerability_alert(comment.alert)
    when RepositoryAdvisory
      summarize_repository_advisory(comment)
    when RepositoryAdvisoryComment
      summarize_repository_advisory_thread(comment)
    when RepositoryAdvisoryEvent
      summarize_repository_advisory(comment.repository_advisory)
      summarize_standard_comments(comment)
    when VulnerabilityAlertingEvent::VulnerableRepositoryNotification
      summarize_vulnerable_repository_notification_thread(comment)
    when VulnerabilityAlertingEvent::SecurityAdvisoryNotification
      summarize_security_advisory_notification_thread(comment)
    when GateRequest
      summarize_workflow_run(comment.workflow_run)
      summarize_comment(comment)
    when CheckSuiteEventNotification
      summarize_check_suite(comment)
      summarize_comment(comment, created_at: comment.updated_at.to_i)
    when Discussion
      summarize_discussion(comment)
    when DiscussionComment
      summarize_discussion_thread(comment)
    when DiscussionEvent::Notification
      summarize_discussion_thread(comment.discussion)
    when MemberFeatureRequest::Notification
      summarize_member_feature_request(comment)
    when MemexProjectStatus
      summarize_memex_project_status(comment)
    else
      raise ArgumentError, "Can't summarize a thread for #{Newsies::Comment.to_key(comment)}"
    end
  rescue Zlib::Error
    GitHub.dogstats.increment("notification_summary", tags: ["action:gzip_save"])
    raise SaveError
  end

  # Internal: Gets the latest ID of the given class that has been summarized.
  #
  # klass - A Class.
  #
  # Returns a positive Integer.
  def latest_summarized_comment_id(klass)
    max = 0
    klass_s = klass.to_s
    items.each_key do |key|
      key_class, key_id = key.split(ITEM_KEY_SEPARATOR)
      next unless key_class == klass_s
      id = T.let(key_id.to_i, Integer)
      max = id if id > max
    end
    max
  end

  ###
  # Summarize all unsummarized records
  ###

  # Internal: Ensures every comment of an Issue, and every review comment of
  # a PullRequest is summarized.
  #
  # issue - The Issue subject of the notification.
  # pull  - Optional PullRequest of the Issue, if there is one.
  #
  # Returns nothing.
  def summarize_issue_thread(issue, pull = nil)
    # Ensure parent issue is summarized
    summarize_issues(issue) unless self.title.present?

    self.is_pull_request = !!issue.pull_request_id
    self.issue_state = issue.state
    pull ||= issue.pull_request? && issue.pull_request
    issue_comment_id = latest_summarized_comment_id(IssueComment)
    review_id = pull && latest_summarized_comment_id(PullRequestReviewComment)

    if issue_comment_id.zero? || review_id.try(:zero?)
      summarize_issues(issue)
    end

    issue.comments.where("id > ?", issue_comment_id).
      each { |c| summarize_issue_comments(c) }

    if pull
      self.issue_state = pull.state.to_s
      pull.review_comments.where("id > ?", review_id).
        each { |c| summarize_pull_request_review_comments(c) }
    end
  end

  # Internal: Ensures every comment on the Commit has been indexed.
  #
  # repository - The Repository of the Commit.
  # commit_id  - The String Commit ID.
  #
  # Returns nothing.
  def summarize_commit_thread(repository, commit_id)
    summarize_commit thread
    latest_id = latest_summarized_comment_id(CommitComment)
    CommitComment.where(
      "repository_id = ? and commit_id = ? and id > ?",
      repository.id, commit_id, latest_id
    ).each { |c| summarize_commit_comments(c) }
  end

  def summarize_gist_thread(gist)
    user_id = summarize_author(gist.user)
    summarize_comment gist, body: gist.description, user_id: user_id
    self.title ||= gist.title
    self.creator_id = user_id

    latest_id = latest_summarized_comment_id(GistComment)
    GistComment.where(
      "gist_id = ? and id > ?", gist.id, latest_id
    ).each { |c| summarize_standard_comments(c) }
  end

  def summarize_member_feature_request(member_feature_request_notification)
    self.title = member_feature_request_notification.body
    self.creator_id ||= member_feature_request_notification.user.id

    notification = MemberFeatureRequest::Notification.find_by(
      entity_id: member_feature_request_notification.entity_id,
      feature: member_feature_request_notification.feature,
      user_id: member_feature_request_notification.user_id
    )
    summarize_standard_comments(notification)
  end

  ###
  # Summarize individual records
  ###

  # Summarizes the initial Issue.  Issues summarize themselves as the initial
  # comment on the thread.
  #
  # issue - An Issue.
  #
  # Returns nothing.
  def summarize_issues(issue)
    self.is_pull_request = !!issue.pull_request_id
    self.is_draft = issue.pull_request&.draft
    self.title = issue.title
    self.number = self.issue_number = issue.number
    self.creator_id = issue.user_id
    self.issue_state = if is_pull_request
      issue.pull_request.state
    else
      issue.state
    end

    summarize_author issue.user
    summarize_comment issue
  end

  # Summarizes a standard comment type object. Anything that responds to #user,
  # #body, #created_at can be provided here.
  #
  # comment - An comment type object.
  #
  # Returns nothing.
  def summarize_standard_comments(comment)
    summarize_author comment.user
    summarize_comment comment
  end

  # Summarizes an Issue Comment.
  #
  # comment - An IssueComment.
  #
  # Returns nothing.
  def summarize_issue_comments(comment)
    summarize_standard_comments comment
  end

  # Summarizes a Pull Request Review. We use the review's submitted_at
  # field instead of created_at.
  #
  # pull_request_review - The PullRequestReview.
  #
  # Returns nothing.
  def summarize_pull_request_review(pull_request_review)
    summarize_comment(pull_request_review, {
      body: pull_request_review.notifications_summary_title,
      created_at: pull_request_review.submitted_at.to_i,
      permalink: pull_request_review.notifications_permalink,
    })
  end

  # Summarizes a Pull Request Review Comment.
  #
  # review_comment - The PullRequestReviewComment.
  #
  # Returns nothing.
  def summarize_pull_request_review_comments(review_comment)
    return unless review_comment.legacy_comment?

    summarize_standard_comments review_comment
  end

  # Summarize a PullRequestPushNotification
  #
  # pull_request_push_notification - The PullRequestPushNotification
  #
  def summarize_pull_request_push_notification(pull_request_push_notification)
    # Ensure parent issue is summarized
    summarize_issues(pull_request_push_notification.issue) unless self.title.present?


    # If this was a force push, remove all other PullRequestPushNotifications from the
    # summary as it's likely they are no longer valid
    if pull_request_push_notification.try(:non_fast_forward?)
      delete_items_of_type(Newsies::Comment.type_from_class(PullRequestPushNotification), before_time: pull_request_push_notification.pushed_at)
    end

    summarize_standard_comments(pull_request_push_notification)
  end

  # Summarizes a Commit Comment.
  #
  # comment - The CommitComment.
  #
  # Returns nothing.
  def summarize_commit_comments(comment)
    summarize_standard_comments comment
  end

  # Summarize commit for CommitComments and CommitMentions.
  #
  # commit - The Commit
  #
  # Returns nothing.
  def summarize_commit(commit)
    user_id = summarize_author(commit.author || commit.author_name)
    summarize_comment commit, body: "", user_id: user_id
    self.title ||= commit.short_message_text
    self.creator_id = user_id
  end

  # Adds the given user to the stored #authors Hash.
  #
  # user - A User or a String login.
  #
  # Returns the Integer user ID.
  def summarize_author(user)
    login = user.to_s
    user_id = user.is_a?(User) ? user.id : login
    authors[user_id] = login
    user_id
  end

  # Adds the given comment to the stored #items Hash.  It is assumed that
  # most comments have the same properties: #body, #created_at, #user_id.
  # In the case that you are summarizing something weird, you can override
  # any of these:
  #
  #   summarize_comment(commit, :body => "", :user_id => 123)
  #
  # comment - Any kind of comment.
  # options - Optional Hash of exceptions for the stored comment.
  #           :body       - Specifies an alternate String body.
  #           :created_at - Specifies an alternate Integer timestamp in
  #                         seconds.
  #           :user_id    - Specifies an alternate User ID that matches a
  #                         value in the #authors hash.
  #
  # Returns nothing.
  def summarize_comment(comment, options = {})
    options[:body] ||= truncate_body comment
    options[:permalink] ||= comment.permalink if comment.respond_to?(:permalink)
    options[:created_at] ||= comment.created_at.to_i
    user_id = (options[:user_id] ||= comment.user_id).to_s
    authors[user_id] ||= comment.user.to_s if comment.respond_to?(:user)
    set_item comment, options
  end

  def summarize_release(release)
    self.title = release.display_name
    self.creator_id = release.author_id
    self.release_tag = release.tag_name

    summarize_author release.author
    summarize_comment release, created_at: release.published_at,
      user_id: release.author_id
  end

  def summarize_repository_invitation(invitation, options = {})
    self.title = invitation.summary
    self.creator_id = invitation.inviter_id
    options[:permalink] = invitation.permalink
    options[:user_id] = summarize_author(invitation.inviter)
    set_item invitation, options
  end

  # Internal: Summarizes a DiscussionPost.
  #
  # post - a DiscussionPost
  #
  # Returns nothing.
  def summarize_discussion_post(post)
    self.title = post.title
    summarize_standard_comments(post)
  end

  # Internal: Summarizes an entire DiscussionPost thread.
  #
  # reply - The new DiscussionPostReply triggering this summarization.
  #
  # Returns nil.
  def summarize_discussion_post_thread(reply)
    # Make sure parent discussion post is included in summary.
    summarize_discussion_post(reply.discussion_post) unless self.title.present?

    # Summarize all replies that have yet to be summarized.
    latest_summarized_reply_id = latest_summarized_comment_id(DiscussionPostReply)
    reply.discussion_post.replies.where("id > ?", latest_summarized_reply_id).each do |single_reply|
      summarize_standard_comments(single_reply)
    end

    nil
  end

  # Internal: Summarizes an AdvisoryCredit
  #
  # advisory_credit - an AdvisoryCredit
  #
  # Returns nothing.
  def summarize_advisory_credit(advisory_credit)
    author = advisory_credit.notifications_author
    self.title = advisory_credit.notification_summary_title
    self.creator_id = author&.id

    summarize_author(author)
    summarize_comment(advisory_credit, {
      body: advisory_credit.notification_summary_body,
      user_id: author&.id,
    })
  end

  # Internal: Summarizes a RepositoryVulnerabilityAlert.
  #
  # repository_vulnerability_alert - a RepositoryVulnerabilityAlert
  #
  # Returns nothing.
  def summarize_repository_vulnerability_alert(repository_vulnerability_alert)
    self.title      = "Potential security vulnerability found in the #{repository_vulnerability_alert.vulnerable_version_range.affects} dependency"
    self.creator_id = repository_vulnerability_alert.notifications_author.id

    author = repository_vulnerability_alert.notifications_author
    summarize_author(author)
    summarize_comment(repository_vulnerability_alert, {
      body: "", # Alerts don't have a body
      user_id: author.id,
    })
  end

  # Internal: Summarizes a RepositoryAdvisory.
  #
  # repository_advisory - a RepositoryAdvisory
  #
  # Returns nothing.
  def summarize_repository_advisory(repository_advisory)
    author = repository_advisory.author

    self.title = repository_advisory.title
    self.number = repository_advisory.ghsa_id
    self.creator_id = author.id
    self.issue_state = repository_advisory.state

    summarize_author(author)

    summarize_comment(repository_advisory, {
      body: truncate_body(repository_advisory.description),
      user_id: author.id,
    })
  end

  # Internal: Summarizes the original post of a Discussion.
  #
  # discussion - a Discussion
  #
  # Returns nothing.
  def summarize_discussion(discussion)
    self.title = discussion.title
    self.number = discussion.number
    self.creator_id = discussion.user_id

    summarize_author(discussion.user)
    summarize_comment(discussion,
      body: truncate_body(discussion.body),
      user_id: discussion.user_id,
    )
  end

  # Internal: Summarizes an entire Discussion thread, including its DiscussionComments.
  #
  # comment - The new DiscussionComment triggering this summarization.
  #
  # Returns nil.
  def summarize_discussion_thread(comment)
    discussion = comment.discussion

    # Make sure parent discussion is included in summary.
    summarize_discussion(discussion) unless self.title.present?

    # Summarize all replies that have yet to be summarized.
    latest_summarized_reply_id = latest_summarized_comment_id(DiscussionComment)
    discussion.comments.after_comment(latest_summarized_reply_id).each do |comment|
      summarize_standard_comments(comment)
    end

    nil
  end

  # Internal: Summarizes an entire RepositoryAdvisory thread.
  #
  # comment - The new RepositoryAdvisoryComment triggering this summarization.
  #
  # Returns nothing.
  def summarize_repository_advisory_thread(comment)
    # Make sure parent advisory is included in summary.
    summarize_repository_advisory(comment.repository_advisory) unless self.title.present?

    # Summarize all comments that have yet to be summarized.
    latest_id = latest_summarized_comment_id(RepositoryAdvisoryComment)
    comment.repository_advisory.comments.where("id > ?", latest_id).each do |comment|
      summarize_standard_comments(comment)
    end
  end

  # Internal: Summarizes an entire VulnerabilityAlertingEvent::SecurityAdvisoryNotification thread.
  #
  # comment - The new VulnerabilityAlertingEvent triggering this summarization.
  #
  # Returns nothing.
  def summarize_security_advisory_notification_thread(comment)
    author = comment.notifications_author

    self.title = comment.notifications_title
    self.number = comment.notifications_thread.ghsa_id
    self.creator_id = author&.id

    summarize_author(author)

    summarize_comment(comment, {
      user_id: author&.id
    })
  end

  # Internal: Summarizes an entire VulnerabilityAlertingEvent::VulnerableRepositoryNotification thread.
  #
  # comment - The new VulnerabilityAlertingEvent triggering this summarization.
  #
  # Returns nothing.
  def summarize_vulnerable_repository_notification_thread(comment)
    author = comment.notifications_author

    self.title = comment.notifications_title
    self.creator_id = author.id

    summarize_author(author)

    summarize_comment(comment, {
      user_id: author.id
    })
  end

  # Internal: Summarizes a CheckSuite.
  #
  # check_suite - a CheckSuite
  #
  # Returns nothing.
  def summarize_check_suite(comment)
    check_suite = comment.check_suite
    status = check_suite.completed? ? StatusCheckConfig.verb_state(check_suite.conclusion) : check_suite.humanized_status

    run_name = check_suite.workflow_run&.explicit_name? ? check_suite.workflow_run.name : check_suite.name
    run_title = "#{run_name} workflow run"

    attempt = check_suite.workflow_run&.latest_workflow_run_execution&.attempt
    run_title += ", Attempt ##{attempt}" if attempt.present? && attempt > 1

    self.title = "#{run_title} #{status} for #{check_suite.head_branch} branch"
    self.number = check_suite.id
    self.creator_id = check_suite.creator_id
    self.check_suite_conclusion = comment.check_suite_conclusion
    self.authors[check_suite.creator_id.to_s] ||= check_suite.creator.to_s
  end

  # Internal: Summarizes a WorkflowRun.
  #
  # workflow_run - a WorkflowRun
  #
  # Returns nothing.
  def summarize_workflow_run(workflow_run)
    self.title = "#{workflow_run.creator.display_login} requested your review to deploy to an environment"
    self.number = workflow_run.id
    self.creator_id = workflow_run.creator_id
    self.authors[workflow_run.creator_id.to_s] ||= workflow_run.creator.to_s
  end

  def trim_item_keys!(limit = nil)
    oldest_item_keys(limit).each do |key|
      items.delete(key)
    end
  end

  # Internal: Summarizes a MemexProjectStatus.
  #
  # memex_project_status - a MemexProjectStatus
  #
  # Returns nothing.
  def summarize_memex_project_status(comment)
    memex_project_status = comment

    self.title = memex_project_status.memex_project.title
    self.number = memex_project_status.memex_project.number
    self.creator_id = memex_project_status.creator_id
    self.authors[memex_project_status.creator_id.to_s] ||= memex_project_status.creator.display_login

    summarize_comment(comment, {
      user_id: memex_project_status.creator.id,
      permalink: memex_project_status.permalink,
    })
  end

  def trim_item_body_html!
    items.each_value do |item|
      item.delete :body_html
      item.delete "body_html"
      item[:body] = truncate_body(item.delete(:body) || item.delete("body"))
    end
  end

  def truncate_body(comment)
    # Working around Issue instances return false for respond_to?(:body) in prod.
    # https://github.com/github/mobile/issues/2325
    body =
      if comment.instance_of?(Issue) || comment.respond_to?(:body)
        comment.body # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      else
        comment
      end

    body.to_s[0..self.class.comment_body_size_threshold.to_i - 1]
  end

  def ordered_item_keys
    keys = []
    thread_item_key = self.thread_item_key
    items.sort do |(_, x), (_, y)|
      (y[:created_at] || y[CREATED_AT_KEY]).to_i <=>
        (x[:created_at] || x[CREATED_AT_KEY]).to_i
    end.each do |(key, _value)|
      keys << key unless key == thread_item_key
    end
    keys
  end

  def oldest_item_keys(limit = nil)
    limit ||= item_limit
    Array(ordered_item_keys[limit..-1])
  end

  def thread_item_key
    thread_key.gsub ";", ":"
  end

  def item_limit
    @item_limit ||= self.class.item_limit
  end

  def log_summary_creation
    log_summary :create
  end

  def log_summary_update
    log_summary :update
  end

  def log_summary(op)
    GitHub.logger.info("saving notification_summary", {
      "code.namespace" => "NotificationSummary",
      "code.function" => "save",
      "gh.notifications.notification_summary.id" => id,
      "gh.notifications.notification_summary.method" => op
    })
  end

  CREATED_AT_KEY = "created_at".freeze

  def newsies_thread
    @newsies_thread ||= Newsies::Thread.from_key(thread_key, list: newsies_list)
  end

  def newsies_list
    @newsies_list ||= Newsies::List.new(list_type, list_id)
  end

  # Public: Returns the most recent comment in the notification summary by created at date.
  #
  # returns Newsies::Comment
  def last_comment
    key = ordered_item_keys.first || thread_item_key

    # Some keys include ":" in them, for example "Grit::Commit:${commit_sha}" so split from the last ":" to find the key, type
    type, _, id = key.rpartition(ITEM_KEY_SEPARATOR)

    @last_comment ||= Newsies::Comment.new(type, id)
  end

  sig { override.returns(String) }
  def flipper_id
    vexi_id
  end

  sig { override.returns(String) }
  def vexi_id
    GitHub::VexiActor.to_feature_flag_id(list_type, list_id)
  end

  sig { override.returns(T::Hash[String, T::Boolean]) }
  def memoized_custom_gates
    @memoized_custom_gates ||= {}
  end

  private

  def reset_lists
    @list = nil
    @newsies_list = nil
  end

  def reset_threads
    # unmemoize thread and newsies thread when thread changes
    @thread = nil
    @newsies_thread = nil
  end

  # Delete all items matching a specific comment type
  # item_type: string of the item type, from Newsies::Comment.to_type(comment_class)
  # before_time: Time - if present only items with a `["created_at"]` older than this will be deleted
  def delete_items_of_type(item_type, before_time: nil)
    item_type_matcher = "#{item_type}#{ITEM_KEY_SEPARATOR}"

    keys_to_delete = items.keys.select do |key|
      next false unless key.starts_with?(item_type_matcher)

      if before_time.present?
        created_at = items[key]["created_at"]

        # skip deleting if it's newer than the specified before time
        next false if created_at.present? && created_at >= before_time.to_i
      end
      true
    end

    keys_to_delete.each { |key| delete_item_by_key(key) }
  end

  def delete_item_by_key(item_key)
    return unless item = items.delete(item_key)
    deleted_author_id = item["user_id"].to_s
    return if deleted_author_id.blank? || creator_id.to_s == deleted_author_id
    if items.none? { |_key, i| i["user_id"].to_s == deleted_author_id }
      authors.delete deleted_author_id
    end
  end
end
