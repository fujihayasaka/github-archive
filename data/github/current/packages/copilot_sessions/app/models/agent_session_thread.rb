# typed: strict
# frozen_string_literal: true

# Lightweight wrapper representing the agent session thread for Newsies web notifications.
# This is deliberately a top-level class (not nested under AgentSessionFinishedNotification)
# because the Newsies thread_key column is varchar(80) and the class name is used as the
# thread type in the key.
class AgentSessionThread
  sig { returns(String) }
  attr_reader :session_id

  sig { returns(String) }
  attr_reader :task_id

  sig { returns(String) }
  attr_reader :session_state

  sig { returns(T.nilable(String)) }
  attr_reader :session_name

  sig { returns(Integer) }
  attr_reader :agent_id

  sig { returns(AgentSessionFinishedNotification) }
  attr_reader :notification

  sig { params(notification: AgentSessionFinishedNotification).void }
  def initialize(notification)
    raise ArgumentError, "AgentSessionThread requires a persisted notification (got id=nil)" unless notification.id

    @notification = T.let(notification, AgentSessionFinishedNotification)
    @session_id = T.let(notification.session_id, String)
    @task_id = T.let(notification.task_id, String)
    @session_state = T.let(notification.session_state, String)
    @session_name = T.let(notification.session_name, T.nilable(String))
    @agent_id = T.let(notification.agent_id, Integer)
  end

  sig { returns(Integer) }
  def id
    # Constructor guarantees the notification is persisted, so id is non-nil.
    T.cast(notification.id, Integer)
  end

  sig { returns(NilClass) }
  def notifications_author
    notification.notifications_author
  end

  sig { params(viewer: User).returns(Promise[T::Boolean]) }
  def async_readable_by?(viewer)
    notification.async_readable_by?(viewer)
  end

  sig { params(viewer: User).returns(T::Boolean) }
  def readable_by?(viewer)
    notification.readable_by?(viewer)
  end

  sig { returns(String) }
  def permalink
    notification.permalink
  end

  sig { returns(T.nilable(String)) }
  def agent_avatar_url
    notification.agent_avatar_url
  end

  sig { returns(String) }
  def agent_display_name
    notification.agent_display_name
  end
end
