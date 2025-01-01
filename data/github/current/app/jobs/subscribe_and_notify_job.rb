# typed: true
# frozen_string_literal: true

class SubscribeAndNotifyJob < ApplicationJob
  include Newsies::Reasons

  include GitHub::Tracing
  trace_method(
    :subscribe_mentioned_teams,
    span_attribute_extractor: ->(_instance, *args, **_kwargs) do
      {
        "gh.notifications.subscribe_and_notify_mentioned_teams.count" => args[1].size
      }
    end
  )

  # Default set of primaries for write operations
  use_primaries ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests

  queue_as :subscribe_and_notify

  # Number of users we want to subscribe in single throttle block
  BATCH_SIZE = 10

  DOG_STATS_PREFIX = "active_job.subscribe_and_notify_job".freeze

  # Discard the job if the subject or author are deleted before the job runs
  discard_on ActiveRecord::RecordNotFound

  DATABASE_UNAVAILABLE_EXCEPTIONS = [
      Freno::Throttler::Error,
      *Resiliency::Response::UnavailableExceptions
    ]

  retry_on *DATABASE_UNAVAILABLE_EXCEPTIONS, wait: :polynomially_longer, attempts: 20

  retry_on_dirty_exit

  resolve_tenant_context do |subject, _|
    Notifications::TenantContext.resolve_tenant(subject&.notifications_list)
  end

  # This receives a subject and a list of users and teams who were mentioned in
  # it and need to be subscribed. After they are we trigger deliver any
  # notifications that need to be sent to subscribers
  #
  # Notifications have to be sent after all subscribing is done otherwise we
  # are open to race conditions where mentioned users don't get notified. That's
  # why we're doing both things in the same job here.
  #
  # subject - The mentionable object that triggered this job
  # opts - A hash containing any of the following:
  #   subscriber_reasons_and_ids - A Hash mapping Symbol reasons to Arrays of subscriber IDs
  #   mentioned_user_ids - An array of IDs representing User objects
  #   mentioned_team_ids - An array of IDs representing Team objects
  #   previous_body - The body as it existed in previous_changes before queueing this job
  #   deliver_notifications - Whether or not we should call `#deliver_notifications`
  #   author - A User object of the user who made the change that queued this job, or nil
  #   author_subscribe_reason - The reason to use for the author's subscription, author won't be subscribed if not provided
  #

  before_enqueue do |job|
    subject, opts = job.arguments
    opts ||= {} # Make sure that opts isn't nil

    GitHub.dogstats.increment("#{DOG_STATS_PREFIX}.before_enqueue", tags: [
      "subject_type:#{subject.class.to_s.underscore}",
      "has_subscribers:#{opts[:subscriber_reasons_and_ids].present?}",
      "has_mentioned_users:#{opts[:mentioned_user_ids].present?}",
      "has_mentioned_teams:#{opts[:mentioned_team_ids].present?}",
      "has_author:#{opts[:author].present?}",
      "has_author_subscribe_reason:#{opts[:author_subscribe_reason].present?}",
      "deliver_notifications:#{opts[:deliver_notifications].present?}",
    ])
  end

  def perform(subject, opts = {})
    GitHub.dogstats.increment(DOG_STATS_PREFIX, tags: [
      "subject_type:#{subject.class.to_s.underscore}",
      "has_subscribers:#{opts[:subscriber_reasons_and_ids].present?}",
      "has_mentioned_users:#{opts[:mentioned_user_ids].present?}",
      "has_mentioned_teams:#{opts[:mentioned_team_ids].present?}",
      "has_author:#{opts[:author].present?}",
      "has_author_subscribe_reason:#{opts[:author_subscribe_reason].present?}",
      "deliver_notifications:#{opts[:deliver_notifications].present?}",
    ])

    # In some cases, users may need to be explicitly subscribed for reasons
    # other than being the author of the subject or being mentioned in its body.
    # For example, a security advisory created on a repository requires that a
    # particular set of users that's equipped to deal with the advisory is
    # automatically subscribed and notified. Passing the reason(s) and
    # subscriber IDs to this job allows us to move a potentially expensive
    # mass subscription operation out of the request and into the background.
    if opts[:subscriber_reasons_and_ids].present?
      opts[:subscriber_reasons_and_ids].each do |reason, user_ids|
        valid_reason = valid_reason_from(reason)
        next unless valid_reason

        users = User.where(id: user_ids)

        if users.any?
          GitHub.tracer.in_span("subscribe_all_users", kind: :internal, attributes: { "gh.notifications.subscribe_and_notify_users.count" => users.size }) do
            users.each_slice(BATCH_SIZE) do |batched_users|
              Newsies::ThreadSubscription.throttle { subject.subscribe_all(batched_users, valid_reason) }
            end
          end
        end
      end
    end

    mentioned_users = load_mentioned_users(subject, opts)

    GitHub.tracer.in_span("subscribe_all_mentioned_users", kind: :internal, attributes: { "gh.notifications.subscribe_and_notify_mentioned_users.count" => mentioned_users.size }) do
      mentioned_users.each_slice(BATCH_SIZE) do |batched_users|
        Newsies::ThreadSubscription.throttle { subject.subscribe_mentioned(batched_users, opts[:author]) }
      end
    end

    mentioned_teams = load_mentioned_teams(subject, opts)

    # A temporary measure to prevent `@epicgames/developers` from being notified
    # See https://github.com/github/platform-health-incidents/issues/486
    if GitHub.flipper[:dont_notify_epicgames_developers].enabled?
      mentioned_teams = mentioned_teams.reject { |team| team.id == Team::NewsiesAdapter::EPICGAMES_DEVELOPER_TEAM_ID }
    end

    # Removes teams with disabled notifications from the list of mentioned teams to prevent them being subscribed
    mentioned_teams = mentioned_teams.reject { |team| team.notifications_disabled? }

    #adding a logger for production testing: check correct removal of mentioned teams with notifications disabled
    mentioned_teams.each do |mentioned_team|
      GitHub.logger.info("SubscribeAndNotifyJob: this team is notified because it has notifications enabled", {
        "code.function": "remove_mentioned_teams_with_disabled_notifications",
        "gh.organization": mentioned_team.organization.display_login,
        "gh.team.name": mentioned_team.name,
        "gh.team.notification_setting": mentioned_team.notification_setting,
      })
    end

    subscribe_mentioned_teams(subject, mentioned_teams, opts[:author]) if mentioned_teams.count

    if opts[:author].present? && opts[:author_subscribe_reason].present?
      GitHub.tracer.in_span("subscribe_author", kind: :internal) do
        Newsies::ThreadSubscription.throttle { subject.subscribe(opts[:author], opts[:author_subscribe_reason].to_sym) }
      end
    end

    if opts[:deliver_notifications]
      GitHub.tracer.in_span("deliver_notifications", kind: :internal) do
        subject.deliver_notifications
      end
    end
  end

  private

  def load_mentioned_users(subject, opts)
    if opts[:mentioned_user_ids].present?
      User.where(id: opts[:mentioned_user_ids])
    elsif opts[:load_mentioned_users]
      subject.mentioned_users
    else
      []
    end
  end

  def load_mentioned_teams(subject, opts)
    if opts[:mentioned_team_ids].present?
      Team.where(id: opts[:mentioned_team_ids])
    elsif opts[:load_mentioned_teams]
      subject.mentioned_teams
    else
      []
    end
  end

  # Subscribe a list of mentioned teams to the given subject.
  #
  # subject - The subscribale subject
  # mentions - Array of teams, or Team scope, that were mentioned.
  # author - The subject's author
  #
  # Returns nothing.
  def subscribe_mentioned_teams(subject, mentioned_teams, author = nil)
    author ||= subject.respond_to?(:user) ? subject.user : nil
    return if author && author.spammy?

    GitHub.dogstats.histogram("#{DOG_STATS_PREFIX}.mentioned_teams", mentioned_teams.size)
    GitHub.dogstats.time("#{DOG_STATS_PREFIX}.subscribe_mentioned_teams") do
      notifications_thread = subject.notifications_thread
      mentioned_teams.each do |mentioned_team|
        team_members = notifications_thread.subscribable_team_members(mentioned_team)
        GitHub.tracer.in_span("subscribe_team_members", kind: :internal, attributes: { "gh.notifications.mentioned_team_members.count" => team_members.size }) do
          GitHub.dogstats.histogram("#{DOG_STATS_PREFIX}.mentioned_team.members", team_members.size)
          GitHub.dogstats.time("#{DOG_STATS_PREFIX}.subscribe_mentioned_team") do
            team_members.each_slice(BATCH_SIZE) do |batched_team_members|
              Newsies::ThreadSubscription.throttle do
                notifications_thread.subscribe_all(batched_team_members, "team-mentioned")
              end
            end
          end
        end
      end
    end

    nil
  end
end
