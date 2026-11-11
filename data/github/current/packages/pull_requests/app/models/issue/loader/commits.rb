# typed: true
# frozen_string_literal: true

class Issue::Loader::Commits < Issue::Loader::Base
  def initialize(context, events: [])
    @context = context
    @events = events
  end

  def self.load_for(context, events: [])
    super new(context, events: events)
  end

  def load
    referenced_events = @events.select { |e| e.event == "referenced" }
    # These are not users, but GitActor. Loading them outside of the
    # context of the Commit would yield to refactor the Commit model.
    # Also the GitActor model guards it's own User models.
    #
    # Todo: Only preload users outside of the commit adapter.
    events_promises = [
      async_preload_attribute(@events, :commit, :async_commit),
    ]

    Promise.all(events_promises).sync

    commits = referenced_events.map(&:commit).compact
    commit_promises = [
      async_preload_attribute(commits, :committer, :async_committer),
      async_preload_attribute(commits, :path, :async_path),
      async_preload_attribute(commits, :on_behalf_of, :async_on_behalf_of),
      async_preload_attribute(commits, :message_body_html, :async_message_body_html),
      async_preload_attribute(commits, :short_message_html, :async_short_message_html),
    ]

    commit_promises << async_preload_attribute(commits, :has_status_check_rollup, :async_has_status_check_rollup?)
      .rescue do |e|
        # if the repositories_actions_checks cluster isn't functional, report the error then
        # return false instead of failing the loader.
        if [ActiveRecord::StatementInvalid, ActiveRecord::ConnectionFailed].include? e.class
          Failbot.report e

          commits.each do |commit|
            # This is not very nice and breaks encapsulation. However, the alternative is to open up
            # the object to this specific scenario by adding a setter, which isn't preferable either.
            commit.instance_variable_set(:@async_has_status_check_rollup, Promise.resolve(false))
          end

          Promise.resolve(true)
        else
          raise e
        end
      end

    commit_event_promise = async_preload_attribute(referenced_events, :direct_reference, :async_direct_reference?)

    commits.group_by(&:repository).each do |repository, commits|
      Commit.prefill_comment_counts(commits, repository)
    end

    Promise.all(commit_promises + [commit_event_promise]).sync
  end

  def self.preload_commit_users(context, events: [])
    new(context, events: events).preload_commit_users
  end

  def preload_commit_users
    users = []
    promises = []

    @events.each do |event|
      next unless event.event == "referenced"
      next unless event.commit

      event.commit.author_actors.each do |actor|
        promises << actor.async_bot
        promises << actor.async_visible_user(@context.viewer).then do |user|
          users << user if user
          user
        end
        promises << event.commit.committer_actor.async_visible_actor(@context.viewer)
      end
    end

    Promise.all(promises).sync
    users
  end
end
