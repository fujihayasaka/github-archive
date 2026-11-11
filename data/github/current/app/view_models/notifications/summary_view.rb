# typed: true
# frozen_string_literal: true

module Notifications
  class SummaryView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    class BrokenSummaryView < StandardError; end

    include ActionView::Helpers::TagHelper
    include ActionView::Helpers::UrlHelper
    include AvatarHelper, BasicHelper, EscapeHelper, HydroHelper

    attr_accessor :list, :current_user, :user_id_map
    attr_writer :muted

    # Instantiate a new view model wrapping a single summarized notification such
    # as commits, issues, etc as seen on github.com/notifications
    def initialize(summary = nil)
      self.summary = summary.deep_dup if summary
      @muted = false
    end

    def is_muted
      @muted
    end

    def authors
      @summary[:authors] || {}
    end

    def title
      @summary[:title]
    end

    def state
      case thread_type
      when :pull_request
        if @summary[:is_draft] && @summary[:issue_state] == "open"
          "draft"
        else
          @summary[:issue_state]
        end
      when :issue, :advisory
        @summary[:issue_state]
      when :check_suite
        check_suite_conclusion_view.summary_state
      else
        "none"
      end
    end

    # Public: thread_type of this particular summarized notification
    #
    # Returns a Symbol
    def thread_type
      case summary_thread_type = @summary[:thread][:type]
      when ::Issue.name
        @summary[:is_pull_request] ? :pull_request : :issue
      when "Grit::Commit", ::Commit.name
        :commit
      when ::Milestone.name
        :milestone
      when ::Release.name
        :release
      when "DiscussionPost" # The "Team discussions" feature
        :discussion
      when "Discussion" # The "Discussions" feature on a repository
        :repo_discussion
      when "Gist"
        :gist
      when "RepositoryInvitation"
        :invitation
      when "RepositoryVulnerabilityAlert", "SecurityAdvisory", "RepositoryDependabotAlertsThread"
        :security_alert
      when "RepositoryAdvisory"
        :advisory
      when "CheckSuite"
        :check_suite
      when "Actions::WorkflowRun"
        :workflow_run
      else
        fail "unknown thread_type #{summary_thread_type}"
      end
    end

    # Public: provide a label for aria-label for assistive devices
    #
    # Returns a String
    def thread_type_label
      label = thread_type.to_s

      if thread_type == :check_suite
        label = [check_suite_conclusion_view.adjective, label].join(" ")
      elsif state != "none"
        label = [state, label].join(" ")
      end

      label.humanize
    end

    # Public: data attributes for the notification link
    #
    # Returns a hash to be used with link_to: `link_to(url, data: link_data_attributes)`
    def link_data_attributes
      data_attributes = {}

      data_attributes.merge!(hovercard_data_attributes)
      data_attributes.merge!(
        hydro_click_tracking_attributes("notifications.read", {
          list_type: @summary[:list][:type],
          list_id: @summary[:list][:id],
          thread_type: @summary[:thread][:type],
          thread_id: @summary[:thread][:id],
          comment_type: last_item[:type],
          comment_id: last_item[:id],
        }),
      )

      data_attributes
    end

    # Public: icon_class for the thread we are summarizing
    #
    # Returns a String
    def icon_class
      case thread_type
      when :issue
        case @summary[:issue_state]
        when "open"
          "issue-opened"
        when "merged"
          "git-merge"
        else
          "issue-closed"
        end
      when :pull_request
        case @summary[:issue_state]
        when "merged"
          "git-merge"
        when "closed"
          "git-pull-request-closed"
        else
          "git-pull-request"
        end
      when :advisory
        case @summary[:issue_state]
        when "closed"
          "shield-x"
        when "published"
          "shield-check"
        else
          "shield"
        end
      when :commit
        "git-commit"
      when :milestone
        "mark-github"
      when :release
        "tag"
      when :discussion, :repo_discussion
        "comment-discussion"
      when :invitation
        "mail"
      when :security_alert
        "alert"
      when :gist
        "code"
      when :check_suite
        check_suite_conclusion_view.icon
      when :workflow_run
        "rocket"
      else
        fail "unknown thread_type: #{thread_type}"
      end
    end

    # Gets the name of the creator of this thread.
    #
    # Returns a String GitHub login or Committer name.
    def creator
      authors[@summary[:creator_id]]
    end

    # Gets the item details for the initial thread.
    #
    # Returns a Hash:
    #   :type       - The String class of the thread.
    #   :id         - The Integer ID of the thread.
    #   :user_id    - The Integer ID of the thread author.
    #   :user       - The String name of the thread author.
    #   :body       - The String body of the thread contents.
    #   :created_at - The Time the thread was created.
    def thread_item
      @thread_item ||= begin
        type = @summary[:thread][:type]
        id = @summary[:thread][:id]
        item_id = "#{type}:#{id}"
        expand_item_hash type, id, @summary[:items].delete(item_id)
      end
    end

    # Returns global relay id for Platform::Models::NotificationThread
    def thread_global_relay_id
      notification_thread = Platform::Models::NotificationThread.new(@summary, user: current_user)
      notification_thread.global_relay_id
    end

    # Gets an Array of commenters for this thread, in chronological order.
    #
    # Returns an Array of String names.
    def commenters
      # commenter_structs is an array of SummaryView::User objects
      @comments ||= commenter_structs.map { |user| user.display_login }.reverse
    end

    # Public: An array of comment avatar tags to iterate over, ordered by
    # the commented time ascending order (latest comment last).
    def commenter_avatar_tags
      @commenter_avatar_tags ||= begin
        if is_summary_for_type?("RepositoryInvitation")
          user = ::User.find_by(id: @summary[:creator_id])
          user_gravatar_link(user)
        else
          safe_join(commenter_records.map { |user| user_gravatar_link(user) }.reverse)
        end
      end
    end

    # Get the path for a commenter
    def commenter_path(commenter)
      urls.user_path(commenter)
    end

    def user_gravatar_link(user)
      link_to(avatar_for(user, 20), commenter_path(user), class: "avatar")
    end

    # Concats the array of Commenters with comma
    #
    # Returns an String of String names.
    def commenters_list
      @commenters_list ||= commenters.reverse.to_sentence
    end

    # The Item that is rendered in the Notification template.
    #
    # Returns an Item.
    def shown_item
      @shown_item ||= (oldest_unread_item || last_item)
    end

    # Gets the oldest unread item.  Requires :last_read_at to be set.
    #
    # Returns an Item.
    def oldest_unread_item
      @oldest_unread_item ||= begin
        read_at = @summary[:last_read_at] || Time.local(2000)
        if updated_since?(read_at, thread_item)
          thread_item
        else
          sorted_items.detect { |item| updated_since?(read_at, item) }
        end
      end
    end

    # Gets the newest Item.
    #
    # Returns an Item.
    def last_item
      @last_item ||= (sorted_items.last || thread_item)
    end

    def latest_commenter_record
      case thread_type
      when :security_alert
        ::User.find_by_login("github")
      when :check_suite
        ::User.find_by(id: @summary[:creator_id])
      else
        commenter_records.last
      end
    end

    # Collects the summarized Item data into the last 3 participators in
    # the thread, in chronological order.
    #
    # Returns an Array of ::User objects.
    def commenter_records
      @commenter_records ||= commenter_structs_to_records(commenter_structs)
    end

    # Collects the summarized Item data into the last 3 participators in
    # the thread, in chronological order.
    #
    # Returns an Array of SummaryView::User objects.
    def commenter_structs
      @commenter_structs ||= all_commenter_structs.last(3)
    end

    # Collects the summarized Item data for the all participators in the
    # thread in chronological order.
    #
    # Returns an Array of SummaryView::User objects.
    def all_commenter_structs
      @all_commenter_structs ||= begin
        commenters = sorted_items.map { |item| item.user }
        commenters.unshift(thread_item.user)
        commenters.compact!
        commenters.reverse!
        commenters.uniq!
        commenters.reverse!
        commenters
      end
    end

    def li_class
      @li_class ||= li_classes * " "
    end

    def mute_button_class
      is_muted ? "unmute-note" : "mute-note"
    end

    def mute_url
      "/notifications/mute?id=#{summary_id}"
    end

    def unmute_url
      "/notifications/unmute?id=#{summary_id}"
    end

    def mark_notifications_url
      base_url = "#{list_path}/notifications/mark?ids=#{summary_id}"
      base_url += "&list_type=team" if @summary[:thread][:type] == "DiscussionPost"
      base_url
    end

    def list_path
      # We don't want to scope URLs for gists
      return if @summary[:thread][:type] == "Gist"
      if p = list.try(:name_with_owner)
        "/#{p}"
      end
    end

    # Internal
    def commenter_id
      @commenter_id ||= shown_item.user.id
    end

    # Converts SummaryView::User objects to User objects.
    #
    # structs - Array of SummaryView::User objects.
    #
    # Returns an Array of matching User objects.
    def commenter_structs_to_records(structs)
      user_ids = []
      structs.each do |struct|
        user_ids << struct.id if struct.exist?
      end
      user_ids_to_records(user_ids)
    end

    def user_ids_to_map(user_ids)
      ::User.where(id: user_ids).index_by { |user| user.id }
    end

    # Converts User ids to User objects.
    #
    # user_ids - Array of User ids.
    #
    # Returns an Array of matching User objects.
    def user_ids_to_records(user_ids)
      map = @user_id_map || {}
      if (missing_user_ids = user_ids - map.keys).present?
        map.update user_ids_to_map(missing_user_ids)
      end

      matched = user_ids.map do |id|
        map[id]
      end
      matched.compact!
      matched
    end

    # Sorts the items in chronological order.
    #
    # Returns an Array of Items.
    def sorted_items
      @sorted_items ||= begin
        thread_item
        @summary[:items].map do |(key, hash)|
          type, id = key.split ":"
          expand_item_hash type, id, hash
        end.sort { |x, y| x.created_at.to_i <=> y.created_at.to_i }
      end
    end

    # Internal: Gets the ID of the Summary.
    #
    # Returns an Integer.
    def summary_id
      @summary[:id]
    end

    # Public: The list ID from the Summary.
    def list_id
      if hash = @summary[:list]
        hash[:id].to_i
      end
    end

    # Public: The list type from the Summary.
    def list_type
      if hash = @summary[:list]
        hash[:type]
      end
    end

    def is_unread
      !!@summary[:unread]
    end

    # Determine if the current user is mentioned in the view.  This data is
    # stored per-user, and returned with Summary Hashes loaded from
    # Newsies::WebHandler.
    #
    # Returns true if the current User is mentioned in the last item.
    def is_mentioned
      return @is_mentioned if defined?(@is_mentioned)
      @is_mentioned = is_mentioned!
    end

    def is_mentioned!
      return false unless @current_user
      return false unless @summary[:mentioned]
      return false unless (body = shown_item.try(:body)).present?
      GitHub::HTML::MentionFilter.mentioned_logins_in(body) do |_, login, _|
        return true if login == @current_user.display_login
      end
      false
    end

    # Public: Determine if the thread has comments.  If the summary has more
    # than one item, it has been commented on.
    #
    # Returns true if is commented
    def is_commented
      shown_item != thread_item && sorted_items.size > 0
    end

    def issue_path(with_anchor: true)
      base_path = "%s/issues/%d" % [list.permalink, @summary[:number]]
      if with_anchor
        add_anchor_to(base_path)
      else
        base_path
      end
    end

    def pull_request_path(with_anchor: true)
      base_path = "%s/pull/%d" % [list.permalink, @summary[:number]]
      if with_anchor
        add_anchor_to(base_path)
      else
        base_path
      end
    end

    def hovercard_type
      return @hovercard_type if defined? @hovercard_type
      @hovercard_type = if thread_type == :issue
        "issue"
      elsif thread_type == :pull_request
        "pull_request"
      end
    end

    def show_hovercard?
      hovercard_type.present?
    end

    def hovercard_data_attributes
      return {} unless show_hovercard?

      {
        "hovercard-type" => hovercard_type,
        "hovercard-url" => hovercard_url(show_subscription_status: true),
      }
    end

    def hovercard_url(show_subscription_status: false)
      base_path = if hovercard_type == "issue"
        issue_path(with_anchor: false)
      elsif hovercard_type == "pull_request"
        pull_request_path(with_anchor: false)
      end
      return unless base_path

      url_template = Addressable::Template.new("#{base_path}/hovercard{?query*}")
      query_params = { "show_subscription_status" => show_subscription_status }

      if comment_type = hovercard_comment_type
        query_params["comment_id"] = shown_item.id
        query_params["comment_type"] = comment_type
      end

      url_template.expand({ "query" => query_params }).to_s
    end

    def hovercard_comment_type
      case shown_item.type
      when IssueComment.name
        IssueOrPullRequestHovercard::ISSUE_COMMENT_TYPE
      end
    end

    # Returns the String URL to the thread (issue, commit, ...) on GitHub.
    def url
      return shown_item.permalink if shown_item.permalink.present?

      case thread_type
      when :issue
        issue_path
      when :pull_request
        pull_request_path
      when :commit
        add_anchor_to("%s/commit/%s" % [
          list.permalink,
          @summary[:thread][:id]])
      when :milestone
        add_anchor_to("%s/milestones/%s" % [
          list.permalink,
          @summary[:milestone_slug],
        ])
      when :release
        "%s/releases/tag/%s" % [
          list.permalink,
          UrlHelper.escape_branch(@summary[:release_tag]),
        ]
      when :invitation
        list.permalink
      when :security_alert
        list.permalink
      when :advisory
        add_anchor_to(urls.repository_advisory_url(list.owner, list, @summary[:number], host: GitHub.host_name))
      else
        fail "unknown thread_type: #{thread_type}"
      end
    end

    def issue_number
      case thread_type
      when :issue, :pull_request
        "##{@summary[:issue_number]}"
      when :commit
        "##{@summary[:thread][:id]}"
      when :milestone
        @summary[:milestone_slug]
      else
        ""
      end
    end

    # The sha of the commit.
    #
    # Returns a String.
    def sha
      thread_item.id[0, 10]
    end

    # The updated_at timestamp of the summary
    #
    # Also will report errors on getting the updated_at from the summary
    # See https://github.com/github/github/issues/36551
    def updated_at
      if @summary
        report_broken_summary("Nil updated_at on summary") if @summary[:updated_at].nil?
      end
      @summary[:updated_at]
    end

    # The updated timestamp of the summary, returned inside a <time> element
    #
    # Returns a <time> element String
    def updated_in_words
      if updated_at
        time_ago_in_words_js(updated_at)
      end
    end

    # Determines if the given Item was authored by the given user.
    #
    # item - An Item object.
    # user - Optional User object.  Default: self.current_user.
    #
    # Returns a Boolean.
    def authored?(item, user = nil)
      user ||= @current_user
      user && item.user.id == user.id
    end

    # Determines if the Item has been updated since the given date, and not
    # authored by the current user.
    #
    # time - A Time specifying when the current user read this summary last.
    # item - An Item object.
    #
    # Returns a Boolean.
    def updated_since?(time, item)
      time < item.created_at && !authored?(item)
    end

    def []=(key, value)
      (@summary ||= {})[key] = value
    end

    def summary=(summary)
      @summary = {}
      summary.each do |key, value|
        key_sym = key.to_sym
        case key_sym
        when :thread then value.symbolize_keys!
        when :items
          if value
            value.each_value(&:symbolize_keys!)
          else
            value = {}
          end
        end
        @summary[key_sym] = value
      end
      @summary[:number] ||= @summary[:issue_number] || @summary[:thread][:id]
    end

    def li_classes
      classes = %w(js-notification js-navigation-item)
      classes << (is_unread ? "unread" : "read")
      classes << "mention-note" if is_mentioned
      classes << "muted" if is_muted
      classes << "#{thread_type.to_s.underscore.dasherize}-notification"
    end

    def add_anchor_to(url)
      if (item = shown_item) && (item != thread_item) && (anchor = anchor_for(item))
        url << anchor << item.id
      end

      url
    end

    def anchor_for(comment)
      case comment.type
      when Issue.name, IssueEventNotification.name then nil
      when IssueComment.name then "#issuecomment-"
      when PullRequestReview.name then "#pullrequestreview-"
      when PullRequestReviewComment.name then "#discussion_r"
      when CommitComment.name then "#commitcomment-"
      when RepositoryAdvisoryComment.name then "#advisory-comment-"
      when RepositoryAdvisoryEvent.name then "#event-"
      when DiscussionComment.name then "##{DiscussionComment::DOM_ID_PREFIX}"
      else
        raise ArgumentError, "Can’t build anchor for #{Newsies::Comment.to_key(comment)}"
      end
    end

    def expand_item_hash(type, id, hash)
      hash ||= {}
      user_id = hash[:user_id]
      seconds = hash[:created_at].to_i

      Item.new type, id, User.new(user_id.to_i, authors[user_id.to_s]),
        hash[:body], Time.at(seconds), hash[:permalink]
    end

    def show_mute_button?
      !(is_summary_for_type?("RepositoryInvitation") || is_summary_for_type?("Release"))
    end

    private

    def check_suite_conclusion_view
      @_check_suite_conclusion_view ||=
        CheckSuiteConclusionView.new(@summary[:check_suite_conclusion])
    end

    # Internal: report a broken summary to Failbot to try and help debugging
    # We are somehow getting in some sort of state with busted
    # summaries when showing notifications in the UI.  This is
    # an attempt to get more information on those issues.
    def report_broken_summary(message)
      e = BrokenSummaryView.new(message)
      e.set_backtrace(caller)

      Failbot.report_user_error e
    end

    def is_summary_for_type?(type)
      @summary[:thread][:type] == type
    end

    Item = Struct.new(:type, :id, :user, :body, :created_at, :permalink)

    class User
      attr_accessor :id, :login

      def initialize(id = nil, login = nil)
        @id    = id
        @login = login
      end

      def exist?
        id > 0
      end

      def display_login
        ::User.to_display_login(@login)
      end

      def hash
        id.hash ^ login.hash # rubocop:disable GitHub/DoNotAllowLogin
      end

      def eql?(other_user)
        @id == other_user.id && display_login == other_user.display_login
      end

      alias to_s display_login
    end
  end
end
