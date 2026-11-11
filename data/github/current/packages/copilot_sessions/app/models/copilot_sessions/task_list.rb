# typed: strict
# frozen_string_literal: true

module CopilotSessions
  class TaskList
    extend CapiResource

    sig do
      params(
        user: User,
        token: T.nilable(T.any(Copilot::EncryptedToken, Copilot::DecryptedToken)),
        entry_point: Symbol,
        page_number: T.nilable(Integer),
        page_size: T.nilable(Integer),
        sort_field: T.nilable(TaskSortField),
        sort_direction: T.nilable(SortDirection),
        session_states: T.nilable(T::Array[SessionState]),
      ).returns(TaskList)
    end
    def self.for_user(
      user:,
      token:,
      entry_point: :agent_tasks_for_user,
      page_number: nil,
      page_size: nil,
      sort_field: nil,
      sort_direction: nil,
      session_states: nil
    )
      capi = capi_client(user:, entry_point: entry_point, token:)

      response = capi.list_user_swe_agent_resources(
        page_number:,
        page_size:,
        sort_field: sort_field ? sort_field.serialize : nil,
        sort_direction: sort_direction ? sort_direction.serialize : nil,
        session_states: session_states ? session_states.map(&:serialize) : nil
      )

      hash = sync_capi_response(response)

      from_raw(hash)
    end

    sig { params(hash: T::Hash[String, T.untyped]).returns(TaskList) }
    def self.from_raw(hash)
      resources = hash["resources"] || []
      has_next_page = hash["has_next_page"] || false
      tasks = Task.from_raw(resources)

      new(tasks:, has_next_page:)
    end

    sig { returns(T::Array[Task]) }
    attr_reader :tasks

    sig { returns(T::Boolean) }
    attr_reader :has_next_page

    sig { params(tasks: T::Array[Task], has_next_page: T::Boolean).void }
    def initialize(tasks:, has_next_page:)
      @tasks = tasks
      @has_next_page = has_next_page
    end
  end
end
