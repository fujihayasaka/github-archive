# typed: false
# frozen_string_literal: true

module Stratocaster
  class Event
    class TargetForConditionalAccessMissingError < StandardError
    end

    MAX_COMMITS_TO_SHOW = 2

    COMMIT_COMMENT_EVENT              = Attributes::CommitComment::EVENT_TYPE
    CREATE_EVENT                      = Attributes::Create::EVENT_TYPE
    DELETE_EVENT                      = Attributes::Delete::EVENT_TYPE
    FOLLOW_EVENT                      = Attributes::Follow::EVENT_TYPE
    FORK_EVENT                        = Attributes::Fork::EVENT_TYPE
    GOLLUM_EVENT                      = Attributes::Gollum::EVENT_TYPE
    ISSUE_COMMENT_EVENT               = Attributes::IssueComment::EVENT_TYPE
    ISSUES_EVENT                      = Attributes::Issues::EVENT_TYPE
    MEMBER_EVENT                      = Attributes::Member::EVENT_TYPE
    PUBLIC_EVENT                      = Attributes::Public::EVENT_TYPE
    PULL_REQUEST_EVENT                = Attributes::PullRequest::EVENT_TYPE
    PULL_REQUEST_REVIEW_EVENT         = Attributes::PullRequestReview::EVENT_TYPE
    PULL_REQUEST_REVIEW_COMMENT_EVENT = Attributes::PullRequestReviewComment::EVENT_TYPE
    PUSH_EVENT                        = Attributes::Push::EVENT_TYPE
    RELEASE_EVENT                     = Attributes::Release::EVENT_TYPE
    WATCH_EVENT                       = Attributes::Watch::EVENT_TYPE
    SPONSOR_EVENT                     = Attributes::Sponsor::EVENT_TYPE

    WORKFLOW_EVENT_TYPES = [
      COMMIT_COMMENT_EVENT,
      DELETE_EVENT,
      ISSUE_COMMENT_EVENT,
      PULL_REQUEST_REVIEW_COMMENT_EVENT,
    ].freeze

    NO_ACTION = :none
    LABELED_ACTION = :labeled

    def self.labeled_event?(action)
      action&.to_sym == LABELED_ACTION
    end

    delegate \
      :action,
      :before_sha,
      :comment_commit_id,
      :comment_id,
      :commits,
      :download_id,
      :download_name,
      :forkee_full_name,
      :forkee_id,
      :head_sha,
      :help_wanted_label_name,
      :issue_id,
      :issue_body,
      :issue_comments_count,
      :issue_number,
      :issue_state,
      :issue_title,
      :label_color,
      :label_name,
      :maintainer_id,
      :member_id,
      :object,
      :organization_id,
      :pages,
      :pull_request_body,
      :pull_request_comments_count,
      :pull_request_id,
      :pull_request_number,
      :pull_request_state,
      :pull_request_title,
      :pull_request_url,
      :push_id,
      :pusher_type,
      :sponsor_id,
      :target_bio,
      :target_login,
      :target_type,
      :target_name,
      :target_avatar_url,
      :target_followers_count,
      :target_public_repos_count,
      :ref,
      :ref_type,
      :release_assets,
      :release_id,
      :release_name,
      :release_mentions,
      :release_short_description_html,
      :release_short_description_html_truncated?,
      :release_tag_name,
      :review_id,
      :team_id,
      :team_name,
      :user_id,
      to: :payload_attributes

    ID = "id".freeze
    include Horcrux::Entity

    attr :string, :id, :event_type, :url
    attr :hash, :sender, :user, :org, :repo, :payload
    attr :bool, :public
    attr :time, :created_at, :updated_at

    attr :array, :team_members, :states
    attr :string, :error_message, :backtrace  # rubocop:disable Lint/DuplicateMethods

    attr_accessor :store

    # Public: Returns the database ID of the user who triggered this event.
    def sender_id
      sender[ID] if sender
    end

    # Public: Returns the display name of the user who triggered this event.
    def sender_name
      sender_record.try(:profile_name)
    end

    # Public: The value for the ID key of the Stratocaster::Event's `repo` hash
    # attr. Returns the database ID of the repository associated with the event.
    #
    # Returns an Integer.
    def repo_id
      repo[ID] if repo
    end

    def repo_nwo
      repo_record&.name_with_display_owner
    end

    def repo_description
      repo_record&.description
    end

    def repo_help_wanted_issues_count
      repo_record&.help_wanted_issues_count
    end

    def repo_language_name
      repo_record&.primary_language_name.presence
    end

    def repo_stargazers_count
      repo_record&.stargazer_count
    end

    def repo_pushed_at
      pushed_at = repo_record&.pushed_at

      if pushed_at.present?
        pushed_at.to_s
      end
    end

    def repo_owner
      repo_record&.owner
    end

    def actor_id
      payload_attributes.actor_id || sender[ID]
    end

    def actor_login
      return @actor_login if defined?(@actor_login)
      @actor_login = if @sender_record
        if @sender_record.is_a?(Bot)
          @sender_record.slug
        else
          GitHub.flipper[:use_display_login_for_stratocaster_events].enabled? ? @sender_record.display_login : @sender_record.login
        end
      else
        payload_attributes.actor_login.presence || sender["display_login"]
      end
    end

    def user=(value)
      case value
      when Hash
        @user = value
      when User
        login = GitHub.flipper[:use_display_login_for_stratocaster_events].enabled? ? value.display_login : value.login
        user.update(ID => value.id, "login" => login,
                    "display_login" => value.display_login,
                    "gravatar_id" => "")
      when nil
        @user = nil
      else
        raise ArgumentError, "Invalid: #{value.class}"
      end
    end

    def sender=(value)
      @sender_record = nil

      case value
      when Hash
        @sender = value
      when User
        login = GitHub.flipper[:use_display_login_for_stratocaster_events].enabled? ? value.display_login : value.login
        @sender_record = value
        sender.update(ID => value.id, "login" => login,
                      "display_login" => value.display_login_legacy,
                      "gravatar_id" => "")
      when nil
        @sender = nil
      else
        raise ArgumentError, "Invalid: #{value.class}"
      end
    end

    def org=(value)
      @org_record = nil

      case value
      when Hash
        @org = value
      when Organization
        login = GitHub.flipper[:use_display_login_for_stratocaster_events].enabled? ? value.display_login : value.login
        @org_record = value
        org.update(ID => value.id, "login" => login,
                   "gravatar_id" => "")
      when nil
        @org = nil
      else
        raise ArgumentError, "Invalid: #{value.class}"
      end
    end

    def repo=(value)
      @repo_record = nil

      case value
      when Hash
        @repo = value
      when Repository
        @repo_record = value
        name = GitHub.flipper[:use_display_login_for_stratocaster_events].enabled? ? value.name_with_display_owner : value.name
        repo.update(ID => value.id, "name" => value.name,
                    "source_id" => value.source_id)
        self.user   = value.user
        self.public = value.public?
        self.org    = value.organization if value.in_organization?
      when nil
        @repo = nil
      else
        raise ArgumentError, "Invalid: #{value.class}"
      end
    end

    def url=(address)
      if address.nil?
        @url = nil
      else
        @url = address.to_s
        @url = "/#{@url.sub(/^\//, '')}" if @url !~ /^https?\:/
        @url
      end
    end

    def public?
      public || !!(event_type =~ /^(Follow|Sponsor)/i)
    end

    # Public: Checks if the creator of this event is marked as spammy.
    #
    # Returns a Boolean, true if the event creator is spammy.
    def spammy_sender?
      sender_record.try(:spammy?) || false
    end

    def visible_commits
      (commits || []).last(MAX_COMMITS_TO_SHOW)
    end

    # Public: Get a list of the unique, lowercase commit author email addresses for this event, if
    # it's a push event.
    #
    # Returns an Array of Strings.
    def commit_author_emails
      return [] unless push_event? && visible_commits.present?

      @commit_author_emails ||= visible_commits.
        select { |commit_hash| commit_hash[:author] }.
        map { |commit_hash| commit_hash[:author][:email].presence }.
        compact.map(&:downcase).uniq
    end

    # Public: Specify that the given email represents the given user. Used for preloading commit
    # authors for later use. Does nothing if the given email is not represented in one of this
    # event's commits.
    #
    # email - String; lowercase email address
    # user - User instance
    #
    # Returns nothing.
    def set_commit_author_for_email(email, user)
      if commit_author_emails.include?(email)
        @commit_authors_by_email ||= {}
        @commit_authors_by_email[email] = user
      end
    end

    # Public: Look up the user who represents the commit author with the given email address.
    #
    # email - String; lowercase email address that is present in one of the commits in this push
    #         event
    #
    # Returns a User or nil.
    def commit_author_for_email(email)
      return unless push_event?

      if @commit_authors_by_email && @commit_authors_by_email[email]
        return @commit_authors_by_email[email]
      end

      return unless commit_author_emails.include?(email)

      @commit_authors_by_email ||= {}
      @commit_authors_by_email[email] = User.find_by_email(email)
    end

    def sender_record
      if @sender_record.nil?
        @sender_record =
          (sender_id.present? && User.find_by_id(sender_id)) || false
      end
      @sender_record || nil
    end
    attr_writer :sender_record

    def repo_record
      if @repo_record.nil?
        @repo_record =
          ((repo_id = repo && repo[ID]).present? &&
          Repository.find_by_id(repo_id)) || false
      end
      @repo_record || nil
    end

    def org_record
      if @org_record.nil?
        @org_record = (org_id.present? &&
          Organization.find_by_id(org_id)) || false
      end
      @org_record || nil
    end

    def org_id
      org && org[ID]
    end

    def user_id
      user && user[ID]
    end

    def target_id
      return @target_id if defined?(@target_id)
      @target_id = payload.dig("target", "id") || payload.dig(:target, :id)
    end

    def target_for_conditional_access
      @target_for_conditional_access ||= self.class.
        multiple_target_for_conditional_access(self).
        values.
        first
    end

    def self.multiple_target_for_conditional_access(events)
      events = Array(events)
      ConditionalAccess::Filter.ensure_with_class(events, Stratocaster::Event)

      users = target_for_conditional_access_records(events)
      id_to_owner = users.each_with_object({}) { |v, h| h[v.id] = v }
      events.each_with_object({}) do |event, h|
        h[event] = id_to_owner.fetch(event.target_for_conditional_access_id) do
          raise TargetForConditionalAccessMissingError,
            "#{event.event_type} with id: #{event.id} can't find User with id: #{event.target_for_conditional_access_id} for use as the TFCA"
        end
      end
    end

    def self.target_for_conditional_access_records(events)
      User.where(id: events.map(&:target_for_conditional_access_id))
    end

    def target_for_conditional_access_id
      if user_event?
        target_id
      else
        user_id
      end
    end

    def issue_record
      return @issue_record if defined?(@issue_record)

      @issue_record = if issue_id.present?
        Issue.find_by_id(issue_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end
    end

    # Public
    def payload_value(*keys)
      value = payload
      keys.each do |key|
        value = value[key] || value[key.to_s]
        return unless value
      end
      value
    end

    # Checks for and strips any `legacy` properties from the event payload.
    # This is primarily used in the events v3 API, and the payloads for
    # non-push service hooks.
    #
    # Returns a Hash.
    def current_payload
      @current_payload ||= begin
        h = payload.dup
        h.delete "legacy"
        h.delete :legacy
        h
      end
    end

    def to_octolytics
      Stratocaster::Octolytics::EventBuilder.new(self).events
    end

    def instrument_view(actor, org, grouped: false)
      GlobalInstrumenter.instrument("news_feed.event.view",
        target_type: NewsFeedAnalytics::TARGET_TYPE_EVENT,
        actor: actor,
        org: org,
        event: to_hydro.merge(grouped: grouped),
      )
    end

    def to_hydro
      dimensions = to_octolytics.first[:dimensions]

      {
        repo_id: dimensions["repo_id"],
        actor_id: dimensions["actor_id"],
        public: dimensions["public"] == true,
        type: event_type,
        target_id: target_id,
        id: id,
      }
    end

    def kind
      @kind ||= event_type.to_s.underscore.chomp("_event")
    end

    def new_record?
      id.nil?
    end

    def ==(other)
      other.class.name =~ /Event/ && other.id == id
    end

    def to_i
      id
    end

    # ActiveRecord
    def cache_key
      "stratocaster/events/%s-%d" % [id, created_at.to_i]
    end

    def last_modified_at
      updated_at
    end

    def viewable_by?(viewer)
      return true if public?
      repo_record && repo_record.pullable_by?(viewer)
    end

    def inspect
      %(#<%s id: %s, type: %s, time: %s, sender: %s, target: %s, repo: %s/%s>) % [
        self.class.name, id || :nil, event_type || :nil, created_at, sender["login"] || actor_login || :nil,
        target_login || :nil, user["login"] || :nil, repo["name"] || :nil]
    end

    def workflow_event?
      WORKFLOW_EVENT_TYPES.include?(event_type)
    end

    def issue_comment_event?
      event_type == ISSUE_COMMENT_EVENT
    end

    def pull_request_review_event?
      event_type == PULL_REQUEST_REVIEW_EVENT
    end

    def pull_request_review_comment_event?
      event_type == PULL_REQUEST_REVIEW_COMMENT_EVENT
    end

    def user_event?
      follow_event? || sponsor_event?
    end

    def create_event?
      event_type == CREATE_EVENT
    end

    def member_event?
      event_type == MEMBER_EVENT
    end

    def follow_event?
      event_type == FOLLOW_EVENT
    end

    def sponsor_event?
      event_type == SPONSOR_EVENT
    end

    def public_event?
      event_type == PUBLIC_EVENT
    end

    def push_event?
      event_type == PUSH_EVENT
    end

    def watch_event?
      event_type == WATCH_EVENT
    end

    def fork_event?
      event_type == FORK_EVENT
    end

    def release_event?
      event_type == RELEASE_EVENT
    end

    def has_add_action?
      action == :add
    end

    def has_labeled_action?
      self.class.labeled_event?(action)
    end

    def repository_ref_type?
      ref_type == RefType::REPOSITORY
    end

    def pull_request_or_issues_event?
      [PULL_REQUEST_EVENT, ISSUES_EVENT].include?(event_type)
    end

    # This feature flag can be used as a kill switch if we see certain events
    # causing fanouts that are causing too much resource consumption. It will
    # cause us to skip fanout for these events which will cause them not to
    # show up in peoples feeds. This should be used sparingly and only if needed
    # to avoid bigger problems.
    def disabled?
      GitHub.flipper[:discard_stratocaster_fanout].enabled?(Stratocaster::EventTypeActor.new(event_type, action))
    end

    def model_attributes
      {
        raw_data: to_hash.except(:id, :updated_at),
        updated_at: updated_at,
      }
    end

    def retrieved_id
      @retrieved_id ||= SecureRandom.uuid
    end

    private

    def payload_attributes
      @payload_attributes ||= Stratocaster::EventPayload.new(payload)
    end
  end
end
