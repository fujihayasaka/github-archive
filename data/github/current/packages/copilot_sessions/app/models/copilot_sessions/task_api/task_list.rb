# typed: strict
# frozen_string_literal: true

module CopilotSessions
  module TaskApi
    # Handles fetching tasks from the CAPI Task API.
    class TaskList
      extend CapiResource

      sig do
        params(
          repository: Repository,
          user: User,
          token: T.nilable(T.any(Copilot::EncryptedToken, Copilot::DecryptedToken)),
          owner_filter: T.nilable(Integer),
          creator_ids: T.nilable(T::Array[Integer]),
          archived_filter: T.nilable(T::Boolean),
          session_states: T.nilable(T::Array[SessionState]),
          task_ids: T::Array[String],
          entry_point: Symbol,
          page_number: T.nilable(Integer),
          page_size: T.nilable(Integer),
          sort_field: T.nilable(SortField),
          sort_direction: T.nilable(SortDirection),
          artifact_type: T.nilable(ArtifactType),
          type: T.nilable(String),
          include_agent_ids: T.nilable(T::Array[Integer]),
          custom_agent_name: T.nilable(String),
          custom_agent_names: T.nilable(T::Array[String]),
          artifact_state: T.nilable(String),
          q: T.nilable(String),
        ).returns(TaskList)
      end
      def self.for_repository(
        repository:,
        user:,
        token:,
        owner_filter: nil,
        creator_ids: nil,
        archived_filter: nil,
        session_states: nil,
        task_ids: [],
        entry_point: :agent_tasks_for_repository,
        page_number: nil,
        page_size: nil,
        sort_field: nil,
        sort_direction: nil,
        artifact_type: nil,
        type: nil,
        include_agent_ids: nil,
        custom_agent_name: nil,
        custom_agent_names: nil,
        artifact_state: nil,
        q: nil
      )
        owner_display_login = T.must(repository.owner).display_login
        repo_name = repository.name
        capi = capi_client(user:, entry_point:, token:)
        response = capi.list_repo_tasks(
          owner_display_login: owner_display_login,
          repo: repo_name,
          owner_filter:,
          creator_ids:,
          archived_filter:,
          session_states: session_states ? session_states.map(&:serialize) : nil,
          task_ids:,
          page_number:,
          page_size:,
          sort_field: sort_field ? sort_field.serialize : nil,
          sort_direction: sort_direction ? sort_direction.serialize : nil,
          artifact_type: artifact_type ? artifact_type.serialize : nil,
          type:,
          include_agent_ids:,
          custom_agent_name:,
          custom_agent_names:,
          artifact_state:,
          q:,
        )
        from_raw(sync_capi_response(response))
      end

      sig do
        params(
          user: User,
          token: T.nilable(T.any(Copilot::EncryptedToken, Copilot::DecryptedToken)),
          entry_point: Symbol,
          page_number: T.nilable(Integer),
          page_size: T.nilable(Integer),
          sort_field: T.nilable(SortField),
          sort_direction: T.nilable(SortDirection),
          session_states: T.nilable(T::Array[SessionState]),
          archived: T.nilable(T::Boolean),
          artifact_type: T.nilable(ArtifactType),
          include_agent_ids: T.nilable(T::Array[Integer]),
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
        session_states: nil,
        archived: nil,
        artifact_type: nil,
        include_agent_ids: nil
      )
        capi = capi_client(user:, entry_point:, token:)
        response = capi.list_user_tasks(
          page_number:,
          page_size:,
          sort_field: sort_field ? sort_field.serialize : nil,
          sort_direction: sort_direction ? sort_direction.serialize : nil,
          session_states: session_states ? session_states.map(&:serialize) : nil,
          archived: archived,
          artifact_type: artifact_type ? artifact_type.serialize : nil,
          include_agent_ids: include_agent_ids
        )

        hash = sync_capi_response(response)

        from_raw(hash)
      end

      sig do
        params(
          user: User,
          token: T.nilable(T.any(Copilot::EncryptedToken, Copilot::DecryptedToken)),
          task_ids: T::Array[String],
          entry_point: Symbol,
          request_timeout_s: T.nilable(Float),
        ).returns(TaskList)
      end
      def self.batch_by_task_ids(
        user:,
        token:,
        task_ids:,
        entry_point: :agent_tasks_batch,
        request_timeout_s: nil
      )
        capi = capi_client(user:, entry_point:, token:)
        response = capi.batch_tasks(task_ids:, request_timeout_s:)
        from_raw(sync_capi_response(response))
      end

      sig do
        params(
          user: User,
          token: T.nilable(T.any(Copilot::EncryptedToken, Copilot::DecryptedToken)),
          automation_id: String,
          entry_point: Symbol,
          page_number: T.nilable(Integer),
          page_size: T.nilable(Integer),
          sort_field: T.nilable(SortField),
          sort_direction: T.nilable(SortDirection),
        ).returns(TaskList)
      end
      def self.for_automation(
        user:,
        token:,
        automation_id:,
        entry_point: :agent_tasks_for_automation,
        page_number: nil,
        page_size: nil,
        sort_field: nil,
        sort_direction: nil
      )
        capi = capi_client(user:, entry_point:, token:)
        response = capi.list_automation_tasks(
          automation_id:,
          page_number:,
          page_size:,
          sort_field: sort_field ? sort_field.serialize : nil,
          sort_direction: sort_direction ? sort_direction.serialize : nil,
        )
        from_raw(sync_capi_response(response))
      end

      sig { params(hash: T::Hash[String, T.untyped]).returns(TaskList) }
      def self.from_raw(hash)
        raw_tasks = hash["tasks"] || []
        has_next_page = parse_has_next_page(hash)
        tasks = raw_tasks.map { |task_data| Task.new(task_data) }

        new(tasks:, has_next_page:)
      end

      # Determines has_next_page from the Link header if present (GitHub REST API convention),
      # falling back to the has_next_page field in the JSON body.
      sig { params(hash: T::Hash[String, T.untyped]).returns(T::Boolean) }
      def self.parse_has_next_page(hash)
        link_header = hash["_link_header"]
        if link_header
          link_header.include?('rel="next"')
        else
          hash["has_next_page"] || false
        end
      end
      private_class_method :parse_has_next_page

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
end
