# typed: true
# frozen_string_literal: true

# This class represents notifications via Notifyd that are sent to users
# when an agent session has finished (completed, failed, etc.)
class AgentSessionFinishedNotification < ApplicationRecord::Domain::Copilot
  include GitHub::Memoizer
  include ::Repositories::BelongsToRepository

  include ::Users::BelongsToUser
  belongs_to_user_via_domain optional: false
  belongs_to_repository_via_domain
  belongs_to :pull_request, optional: true

  validates :user, presence: true
  validates :repository, presence: true
  validates :agent_id, presence: true
  validates :session_id, presence: true
  validates :task_id, presence: true
  validates :session_state, presence: true

  # Newsies adapter interface implementation

  sig { returns(AgentSessionThread) }
  def notifications_thread
    AgentSessionThread.new(self)
  end

  sig { returns(T.nilable(Repositories::IRepository)) }
  def notifications_list
    repository
  end

  # Returns nil because there is no human author for agent-triggered
  # notifications. Returning nil ensures notifications are delivered to the
  # actor rather than skipped.
  sig { returns(NilClass) }
  def notifications_author
    nil
  end

  sig { returns(String) }
  def title
    async_title.sync
  end

  sig { returns(Promise[String]) }
  def async_title
    if session_name.present? && task_name.present? && session_name != task_name
      Promise.new.fulfill("#{task_name} — #{session_name}")
    elsif session_name.present?
      Promise.new.fulfill(session_name)
    elsif task_name.present?
      Promise.new.fulfill(task_name)
    else
      async_agentic_app.then do |agent|
        agent_name = agent&.display_name || "Copilot"
        "#{agent_name} session #{humanized_session_state}"
      end
    end
  end

  sig { returns(String) }
  def body
    async_body.sync
  end

  sig { returns(Promise[String]) }
  def async_body
    Promise.all([async_agentic_app, async_repository]).then do |agent, repo|
      agent_name = agent&.display_name || "Copilot"
      "[#{repo.name_with_display_owner}] #{agent_name} session #{humanized_session_state}"
    end
  end

  sig { returns(String) }
  def permalink
    async_permalink.sync
  end

  sig { returns(Promise[String]) }
  def async_permalink
    Promise.new.fulfill(session_permalink)
  end

  sig { params(viewer: User).returns(Promise[T::Boolean]) }
  def async_readable_by?(viewer)
    return Promise.new.fulfill(false) unless viewer.id == user_id

    async_repository.then { |repo| repo.async_readable_by?(viewer) }
  end

  sig { params(viewer: User).returns(T::Boolean) }
  def readable_by?(viewer)
    async_readable_by?(viewer).sync
  end

  sig { returns(T.nilable(AgenticApp::AgentInstance)) }
  def agentic_app
    async_agentic_app.sync
  end

  sig { returns(Promise[T.nilable(AgenticApp::AgentInstance)]) }
  memoize def async_agentic_app
    Promise.new.fulfill(AgenticApp.agent_for_integration_id(agent_id))
  end

  sig { returns(T.nilable(String)) }
  def agent_avatar_url
    agentic_app&.integration&.preferred_avatar_url(size: 128)
  end

  sig { returns(String) }
  def agent_display_name
    agentic_app&.display_name || "Copilot"
  end

  sig { returns(String) }
  def notification_id
    "/tasks/#{task_id}?session_id=#{session_id}"
  end

  sig { returns(String) }
  def platform_type_name
    "AgentSessionFinishedNotification"
  end

  sig { returns(String) }
  def message_id
    "<#{T.must(repository).name_with_display_owner}/agent_sessions/#{session_id}@#{GitHub.urls.host_name}>"
  end

  private

  sig { returns(String) }
  def humanized_session_state
    session_state
  end

  sig { returns(String) }
  def session_permalink
    repo = T.must(repository)
    "#{GitHub.url}/#{repo.name_with_display_owner}/tasks/#{task_id}?session_id=#{session_id}"
  end

  sig { returns(Promise[Repository]) }
  memoize def async_repository
    Promise.new.fulfill(T.must(repository))
  end
end
