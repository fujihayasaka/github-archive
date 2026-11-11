# typed: true
# frozen_string_literal: true

class HydroAgentSessionFinishedNotificationJob < HydroMessageJob
  queue_as :hydro_agent_session_finished_notification
  retry_on_dirty_exit

  include GitHub::Memoizer

  sig { void }
  def perform
    unless topic == "github.copilot.v0.AgentSessionFinish"
      GitHub.logger.info("AgentSessionFinishedNotification: skipping, topic mismatch", topic: topic)
      return
    end

    if skip_notification?
      GitHub.logger.info("AgentSessionFinishedNotification: skipping, skip_notification flag set",
        user_id: message[:user_id], session_id: message[:session_id])
      return
    end

    unless user.present?
      GitHub.logger.info("AgentSessionFinishedNotification: skipping, user not found", user_id: message[:user_id])
      return
    end

    unless allowed_agent?
      GitHub.logger.info("AgentSessionFinishedNotification: skipping, agent not in allowlist",
        user_id: user&.id, agent_id: agent_id)
      return
    end

    if triage_event?
      GitHub.logger.debug("AgentSessionFinishedNotification: skipping, triage event type",
        user_id: user&.id, event_type: event_type)
      return
    end

    # Only send notifications for sessions without a resource (e.g., no PR)
    if has_resource?
      GitHub.logger.info("AgentSessionFinishedNotification: skipping, session has associated resource",
        user_id: user&.id, resource_type: message[:resource_type], resource_id: message[:resource_id])
      return
    end

    unless repository.present?
      GitHub.logger.info("AgentSessionFinishedNotification: skipping, repository not found",
        user_id: user&.id, repository_id: message[:repository_id])
      return
    end

    unless T.must(repository).readable_by?(T.must(user))
      GitHub.logger.info("AgentSessionFinishedNotification: skipping, user cannot read repository",
        user_id: user&.id, repository_id: repository&.id)
      return
    end

    notification = create_notification
    unless notification
      GitHub.logger.warn("AgentSessionFinishedNotification: failed to create notification",
        user_id: user&.id, repository_id: repository&.id, session_id: session_id, agent_id: agent_id, task_id: task_id)
      return
    end

    publish_notification(notification)
    GitHub.logger.info("AgentSessionFinishedNotification: published notification",
      notification_id: notification.id, user_id: notification.user_id,
      repository_id: notification.repository_id, session_id: notification.session_id)
  end

  private

  sig { returns(T.nilable(User)) }
  memoize def user
    User.find_by(id: message[:user_id])
  end

  sig { returns(T.nilable(Repository)) }
  memoize def repository
    Repository.find_by(id: message[:repository_id])
  end

  sig { returns(T.nilable(PullRequest)) }
  memoize def pull_request
    return nil unless message[:resource_type] == "PullRequest"
    PullRequest.find_by(id: message[:resource_id])
  end

  sig { returns(T::Boolean) }
  def has_resource?
    # A resource exists if there's a resource_type and resource_id associated with the session
    message[:resource_type].present? && message[:resource_id].present?
  end

  sig { returns(T.nilable(Integer)) }
  def agent_id
    value = message[:agent_id]
    return nil if value.nil?
    Integer(value)
  rescue ArgumentError, TypeError
    nil
  end

  sig { returns(T.nilable(String)) }
  def session_id
    message[:session_id]
  end

  sig { returns(T.nilable(String)) }
  def session_state
    message[:session_state]
  end

  sig { returns(T::Boolean) }
  def allowed_agent?
    return false unless agent_id.present? && agent_id != 0

    agent = AgenticApp.agent_for_integration_id(agent_id)
    agent&.finished_notifications_enabled? || false
  end

  sig { returns(T.nilable(String)) }
  def task_id
    message[:task_id]
  end

  sig { returns(T.nilable(String)) }
  def session_name
    message[:session_name]
  end

  sig { returns(T.nilable(String)) }
  def task_name
    message[:task_name]
  end

  sig { returns(T.nilable(String)) }
  def event_type
    message[:event_type]
  end

  sig { returns(T::Boolean) }
  def triage_event?
    event_type == "triage"
  end

  sig { returns(T::Boolean) }
  def skip_notification?
    message[:skip_notification] == true
  end

  sig { returns(T.nilable(AgentSessionFinishedNotification)) }
  def create_notification
    return unless session_id.present? && session_state.present? && agent_id.present? && agent_id != 0 && task_id.present?

    ActiveRecord::Base.connected_to(role: :writing) do
      AgentSessionFinishedNotification.create!(
        user: T.must(user),
        repository: T.must(repository),
        agent_id: T.must(agent_id),
        pull_request: pull_request,
        session_id: T.must(session_id),
        task_id: T.must(task_id),
        session_state: T.must(session_state),
        session_name: session_name,
        task_name: task_name,
      )
    end
  rescue ActiveRecord::RecordInvalid => e
    GitHub.logger.error(
      "Failed to create AgentSessionFinishedNotification",
      error: e.message,
      user_id: user&.id,
      repository_id: repository&.id,
      session_id: session_id
    )
    nil
  end

  sig { params(notification: AgentSessionFinishedNotification).void }
  def publish_notification(notification)
    context = { operation: "agent_session_finished" }
    adapter = Notifyd::SubjectAdapter.adapter_for_subject(notification, context)
    unless adapter&.matches?
      GitHub.logger.info("AgentSessionFinishedNotification: skipping, adapter does not match",
        notification_id: notification.id, user_id: notification.user_id)
      return
    end

    Notifyd::NotifyPublisher.new.publish(
      actor_id: T.must(user).id,
      repository_id: adapter.repository_id,
      owner_id: adapter.owner_id,
      owner_type: adapter.owner_type,
      authzd_attributes: adapter.authzd_attributes,
      saml_enforcement: adapter.saml_enforcement,
      mobile_layout: adapter.mobile_layout,
      email_layout: adapter.email_layout,
      explicit_recipients: adapter.explicit_recipients,
      subject: notification,
      related_topics: adapter.related_topics,
      triggered_at: Time.current,
      trigger: adapter.trigger,
      attributes: adapter.attributes,
      feature_switches: adapter.feature_switches,
      notification_id: adapter.notification_id,
    )
  end
end
