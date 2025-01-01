# typed: false
# frozen_string_literal: true

module Stratocaster
  # These classes are responsible for taking a list of arguments and
  # building the Stratocaster::Event attributes.  Each event type takes
  # a different set of arguments, with different logic for generating
  # the url, targets, and payload of the event.
  class Attributes
    autoload :CommitComment,            "stratocaster/attributes/commit_comment"
    autoload :Create,                   "stratocaster/attributes/create"
    autoload :Delete,                   "stratocaster/attributes/delete"
    autoload :Follow,                   "stratocaster/attributes/follow"
    autoload :Fork,                     "stratocaster/attributes/fork"
    autoload :Gollum,                   "stratocaster/attributes/gollum"
    autoload :IssueComment,             "stratocaster/attributes/issue_comment"
    autoload :Issues,                   "stratocaster/attributes/issues"
    autoload :Member,                   "stratocaster/attributes/member"
    autoload :Public,                   "stratocaster/attributes/public"
    autoload :PullRequest,              "stratocaster/attributes/pull_request"
    autoload :PullRequestReview,        "stratocaster/attributes/pull_request_review"
    autoload :PullRequestReviewComment, "stratocaster/attributes/pull_request_review_comment"
    autoload :Push,                     "stratocaster/attributes/push"
    autoload :Release,                  "stratocaster/attributes/release"
    autoload :Sponsor,                  "stratocaster/attributes/sponsor"
    autoload :Watch,                    "stratocaster/attributes/watch"

    include Scientist

    AUTHORIZATION_IDS_BATCH_SIZE = 5000

    # Returns an instance of Stratocaster::Attributes
    def self.from(*args)
      new.tap { |instance| instance.from(*args) }
    end

    # Returns an instance of Stratocaster::Attributes
    def self.from_event(event)
      new.tap { |instance| instance.from_event(event) }
    end

    # Returns an instance of Stratocaster::Event
    def self.trigger(*args)
      instance = from(*args)
      instance.trigger
    end

    # Returns an instance of Stratocaster::Dispatcher
    def self.dispatcher(service, *args)
      instance = from(*args)
      instance.dispatcher(service)
    end

    # Returns an instance of Stratocaster::Dispatcher
    def dispatcher(service = GitHub.stratocaster)
      if (event_properties = to_hash).present?
        Stratocaster::Dispatcher.new(service, self, event_properties)
      end
    end

    # Returns an instance of Stratocaster::Event
    def trigger
      dispatcher.try(:perform)
    end

    # Parses the given ref for the event payload.
    #
    # ref     - The String git ref.
    #
    # Returns a String for the ref.
    def parse_ref(ref)
      ref.split("/", 3).last if ref
    end

    # Escapes a URL fragment, allowing only "/"'s
    #
    # s - The String fragment to escape.
    #
    # Returns an escaped String.
    def u(s)
      return "" if s.blank?
      CGI.escape(s).gsub /%2F/, "/"
    end

    def set_actor_from_pusher(pusher_id)
      @actor = User.find_by_id(pusher_id.to_i) if pusher_id
      @pusher_type = :user
      if @actor.nil?
        @actor = @repo.created_by_user || @repo.owner
        @pusher_type = :deploy_key
      end
    end

    # Gets the unique targets from a repository's listeners and a user's
    # followers.
    #
    # *args - Array of Users, Repositories, Release, or Integer IDs.
    #
    # Returns an Array of User IDs.
    def targets_for(*args)
      users = []

      args.each do |arg|
        case arg
        when User       then users |= targets_for_followers(arg)
        when Repository then users |= targets_for_watchers(arg)
        when Issue      then users |= targets_for_issue(arg)
        when ::Release  then users |= targets_for_release(arg)
        when Integer    then users << arg
        when nil, false
        else raise(ArgumentError, "Invalid: #{arg.class}")
        end
      end

      users.uniq!
      users.compact!
      users
    end

    private

    def targets_for_followers(user)
      start = Time.now
      user.followers.pluck(:id)
    ensure
      GitHub.dogstats.distribution("stratocaster.targets_for_followers.time", (Time.now - start) * 1000, tags: ["event_type:#{self.class}"])
    end

    def targets_for_watchers(repo)
      start = Time.now
      subscriber_ids_for_repo(repo)
    ensure
      GitHub.dogstats.distribution("stratocaster.targets_for_watchers.time", (Time.now - start) * 1000, tags: ["event_type:#{self.class}"])
    end

    def targets_for_issue(issue)
      start = Time.now
      subscriber_ids_for_repo(issue.repository)
    ensure
      GitHub.dogstats.distribution("stratocaster.targets_for_issue.time", (Time.now - start) * 1000, tags: ["event_type:#{self.class}"])
    end

    def targets_for_release(release)
      start = Time.now
      ids = ::Release::FanoutTargetsCollector.new(release).targets
      if release.repository.public? || ids.empty?
        ids
      else
        batched_permitted_admin_and_member_ids(release.repository, ids)
      end
    ensure
      GitHub.dogstats.distribution("stratocaster.targets_for_release.time", (Time.now - start) * 1000, tags: ["event_type:#{self.class}"])
    end

    def subscriber_ids_for_repo(repo)
      subscriber_ids = GitHub.newsies.subscriber_ids_by_cursor(repo).to_a

      if repo.public? || subscriber_ids.empty?
        subscriber_ids
      else
        permitted_admin_and_member_ids(repo, subscriber_ids)
      end
    end

    def permitted_admin_and_member_ids(repo, subscriber_ids)
      subscribed_member_ids = Authorization.service.actor_ids(
        subject: repo,
        actor_ids: subscriber_ids,
        actor_type: User,
        through: [Team, Organization],
      )

      permitted_subscriber_ids = subscribed_member_ids | subscribed_admin_ids(repo, subscriber_ids)
      unpermitted_subscriber_ids = subscriber_ids - permitted_subscriber_ids
      permitted_subscriber_ids
    ensure
      repo.cleanup_old_users(unpermitted_subscriber_ids) if unpermitted_subscriber_ids.present?
    end

    def batched_permitted_admin_and_member_ids(repo, subscriber_ids)
      subscribed_member_ids = subscriber_ids.each_slice(AUTHORIZATION_IDS_BATCH_SIZE).map do |slice|
        Authorization.service.actor_ids(
          subject: repo,
          actor_ids: slice,
          actor_type: User,
          through: [Team, Organization],
        )
      end.flatten

      permitted_subscriber_ids = subscribed_member_ids | subscribed_admin_ids(repo, subscriber_ids)
      unpermitted_subscriber_ids = subscriber_ids - permitted_subscriber_ids
      permitted_subscriber_ids
    ensure
      repo.cleanup_old_users(unpermitted_subscriber_ids) if unpermitted_subscriber_ids.present?
    end

    def subscribed_admin_ids(repo, subscriber_ids)
      return [] if repo.owner.blank? || subscriber_ids.empty?
      repo.owner.admins.map(&:id) & subscriber_ids
    end
  end
end
