# typed: strict
# frozen_string_literal: true

# Once Turboscan has completed the ingestion of an Analysis
# and computed the diff, it signals on the AlertEvent topic
# all the alert changes.
class HydroCodeScanningAlertEventJob < Repositories::RepositoryHydroMessageJob
  retry_on_dirty_exit
  queue_as :hydro_code_scanning_alert_event

  # Message will be a AlertEvent.proto
  # see https://github.com/github/hydro-schemas/blob/bd32975dd26848a565ab345a620295ec7218f6ff/proto/hydro/schemas/turboscan/v0/alert_event.proto#L9
  #
  sig { void }
  def perform
    return if repository.deleted?

    GitHub.logger.error(
      "Unexpected result is nil",
      "code.namespace" => "HydroCodeScanningAlertEventJob",
      "code.function" => "perform",
      "messaging.source.name" => topic,
      "messaging.kafka.source.partition" => partition,
      "messaging.kafka.message.offset" => offset,
    ) if message[:result].nil?

    return if !GitHub.enterprise? && repository.code_scanning_banned?

    event_from_message(message)&.deliver_later
  end

  private

  # Return a Hook::Event::CodeScanningAlertEvent from the given AlertEvent message
  sig { params(values: T::Hash[Symbol, T.untyped]).returns(T.nilable(Hook::Event::CodeScanningAlertEvent)) }
  def event_from_message(values)
    action =
      case values[:event]
      when :ALERT_CREATED
        :created
      when :ALERT_REOPENED_BY_USER
        :reopened_by_user
      when :ALERT_CLOSED_BY_USER
        :closed_by_user
      when :ALERT_CLOSED_BECAME_FIXED
        :fixed
      when :ALERT_APPEARED_IN_BRANCH
        :appeared_in_branch
      when :ALERT_REAPPEARED
        :reopened
      when :ALERT_DELETED_BY_USER
        # Explicitly ignore deleted events, so that integrators do not start
        # using it until we decide whether we want deletion to occur only
        # at the Analysis level
        nil
      else
        nil
      end
    return nil if action.nil?

    actor_id = values[:actor_id]
    actor_id = nil if actor_id.zero?

    event = Hook::Event::CodeScanningAlertEvent.new(
      action: action,
      repository_id: values[:repository_id],
      alert_number: values[:alert_number],
      commit_oid: values[:commit_oid],
      ref: values[:ref],
      actor_id: actor_id,
      result: values[:result],
    )
    event.attributes[:queued_at] = Time.now.to_f
    event
  end
end
