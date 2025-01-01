# typed: false
# frozen_string_literal: true

class ProcessEventJob < ApplicationJob
  extend Forwardable

  # Allow write connections to these clusters.
  use_primaries ApplicationRecord::Mysql5, # key_values table
    ApplicationRecord::Stratocaster # stratocaster_events table

  queue_as :event
  set_max_redelivery_attempts 0

  class AddMemberIgnored < StandardError; end
  # This exception means the repo the event was for has since been deleted.
  # There's nothing this job can do when that happens.
  # AddMemberIgnored is raised when the ignore_member_added FF is enabled for the actor
  discard_on GitRPC::InvalidRepository, AddMemberIgnored


  # override stats_tags to include stratocaster tags
  def_delegator :dogstats_tags, :all, :stats_tags

  before_perform prepend: true do
    dogstats_tags.event_type = arguments.first

    Failbot.push(
      action: "strat",
      event_type: arguments[0],
      event_args: arguments[1],
    )
  end


  # Due to the way this accesses event data we can mark
  # it as exempt from the tenant context requirement.
  exempt_from_tenant_context_requirement

  # Triggers the actual event.
  #
  # event_type: string (e.g. 'IssueEvent')
  # args: array of args from the event
  #
  # See Stratocaster::Service#queue.
  #
  def perform(event_type, args)
    GitHub.logger.info("gh.stratocaster.event_type" => event_type)

    check_add_member_ignored(event_type, args)

    dispatcher = with_read do
      GitHub.stratocaster.dispatcher(event_type, *args)
    end
    event = Stratocaster::Model.throttle { dispatcher&.perform }

    return if event.blank?

    dogstats_tags.event = event
    GitHub.dogstats.increment("stratocaster.dispatched_event", tags: stats_tags)

    UpdateEventFeedsJob.perform_later(event) if dispatcher.perform_fanout?

    @success = true
  ensure
    record_mysql_metrics(mysql_tags: stats_tags)
    dogstats_tags.success = !!@success
  end

  # Part of https://github.com/github/code-intelligence-ktlo/issues/990
  # If the event_type is Stratocaster::Event::MEMBER_EVENT, the args array will
  # be shaped like [repo_id, user_id, actor_id, :added].
  # The actor will be the repo's owner by default, see https://github.com/github/github/blob/6d4b687d0836e3c5aa4421fc5eeb0f8040cb3e71/packages/repositories/app/models/repository/membership_dependency.rb#L536
  # If the ignore_member_added FF is enabled for actor_id, we raise an exception
  # to discard the job.
  def check_add_member_ignored(event_type, args)
    return unless event_type == Stratocaster::Event::MEMBER_EVENT

    repo_id, user_id, actor_id, _ = args
    actor = User.find_by(id: actor_id)

    return unless actor
    return unless actor.feature_enabled?(:stratocaster_ignore_member_added)
    # We don't want to count this discarded job as a failure or it'll trip our alerts
    # unnecessarily.
    @success = true

    raise AddMemberIgnored
  end

  private

  def record_mysql_metrics(mysql_tags:)
    GitHub::MysqlInstrumenter.queries_per_type_database.each do |db_host, counts|
      counts ||= {}
      host_tag = "rpc_host:#{db_host}"
      tags = mysql_tags + [host_tag]
      GitHub.dogstats.count(
        "job.process_event.rpc.mysql.counts.reads",
        counts[:read].to_i,
        tags: tags,
      )
      GitHub.dogstats.count(
        "job.process_event.rpc.mysql.counts.writes",
        counts[:write].to_i,
        tags: tags,
      )
    end
  end

  def dogstats_tags
    @dogstats_tags ||= Stratocaster::DogstatsTags.new
  end
end
