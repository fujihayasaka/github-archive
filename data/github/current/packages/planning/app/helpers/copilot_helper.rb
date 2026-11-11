# typed: true
# frozen_string_literal: true

module CopilotHelper
  sig { params(user: User).returns(T.nilable(Copilot::EncryptedToken)) }
  def build_copilot_api_token(user)
    actor_session = GitHub.context[:actor_session]
    user_session = UserSession.find_by(id: actor_session)

    CopilotSessions::CopilotApiToken.get_encrypted(
      user:,
      entry_point: :projects,
      user_session:
    )
  rescue CopilotSessions::CopilotApiToken::IntegrationUnavailableError
    nil
  end

  TASK_IDS_BATCH_SIZE = 100

  sig { params(user: User, task_ids: T::Array[String]).returns(T.nilable(T::Array[CopilotSessions::TaskApi::Task])) }
  def fetch_tasks(user:, task_ids:)
    token = build_copilot_api_token(user)

    all_tasks = T.let([], T::Array[CopilotSessions::TaskApi::Task])

    # Avoid sending an excessively long query string by batching task_ids
    task_ids.each_slice(TASK_IDS_BATCH_SIZE) do |task_ids_slice|
      task_list = CopilotSessions::TaskApi::TaskList.batch_by_task_ids(
        user:,
        token:,
        task_ids: task_ids_slice,
        entry_point: :agent_tasks_for_projects
      )
      all_tasks.concat(task_list.tasks)
    end

    all_tasks
  rescue => e
    GitHub.dogstats.increment(
      "memex.fetch_agent_task_states.error",
      tags: ["error:#{e.class.name}"]
    )
    nil
  end
end
