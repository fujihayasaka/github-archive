# typed: strict
# frozen_string_literal: true

module CopilotSessions
  # This model is meant to replace the DeprecatedTask model and provide a more 1:1 mapping to CAPI's resource
  # endpoint. This class represents a resource created by a Copilot Agent (such as a Pull Request).
  # It is meant to model the underlying API response from CAPI where the resource is the parent node and
  # sessions are children.
  class Task
    extend CapiResource

    sig do
      params(
        user: User,
        token: T.nilable(T.any(Copilot::EncryptedToken, Copilot::DecryptedToken)),
        task_id: String,
        entry_point: Symbol,
      ).returns(T.nilable(Task))
    end
    def self.fetch_by_id(
      user:,
      token:,
      task_id:,
      entry_point: :agent_tasks_for_user
    )
      # The ID is in the form of: "resource:{resource_type}:{resource_id}"
      id_parts = task_id.split(":")
      return nil unless id_parts.size == 3

      resource_type = id_parts[1].to_s
      resource_id = id_parts[2].to_i

      for_resource(
        user: user,
        token: token,
        resource_type:,
        resource_id:,
        entry_point: entry_point
      )
    end

    sig do
      params(
        user: User,
        token: T.nilable(T.any(Copilot::EncryptedToken, Copilot::DecryptedToken)),
        resource_type: String,
        resource_id: Integer,
        entry_point: Symbol,
      ).returns(T.nilable(Task))
    end
    def self.for_resource(
      user:,
      token:,
      resource_type:,
      resource_id:,
      entry_point: :agent_tasks_for_user
    )
      capi = capi_client(user:, entry_point:, token:)

      begin
        response = capi.get_swe_agent_resource(resource_type:, resource_id:)
      rescue CopilotAPI::NotFoundError
        return nil
      end

      hash = response.is_a?(ConcurrentFaraday::FutureResponse) ? response.value : response

      # Make sure a populated hash was returned or else treat it like a not found.
      return nil unless hash.present?

      new(hash)
    end

    sig { params(resources: T.nilable(T::Array[T::Hash[String, T.untyped]])).returns(T::Array[Task]) }
    def self.from_raw(resources)
      return [] unless resources

      resources.map do |resource_data|
        new(resource_data.with_indifferent_access)
      end
    end

    sig { returns(T::Hash[String, T.untyped]) }
    attr_reader :raw_resource

    sig { params(raw_resource: T::Hash[String, T.untyped]).void }
    def initialize(raw_resource)
      @raw_resource = raw_resource
    end

    sig { returns(String) }
    def id
      raw_resource["id"]
    end

    sig { returns(String) }
    def last_updated_at
      value = raw_resource["last_updated_at"]

      # The /agents/resource CAPI endpoint will return last_updated_at as a epoch while
      # /agents/sessions/resources returns a ISO-8601 formatted time so we have to handle both cases.
      if value.is_a?(Integer)
        Time.at(value).utc.iso8601
      else
        value
      end
    end

    sig { returns(Integer) }
    def session_count
      raw_resource["session_count"]
    end

    sig { returns(String) }
    def resource_type
      raw_resource["resource_type"]
    end

    sig { returns(Integer) }
    def resource_id
      raw_resource["resource_id"]
    end

    sig { returns(String) }
    def state
      raw_resource["state"]
    end

    sig { returns(T::Array[PartialAgentSession]) }
    def sessions
      # Per CAPI's different resource endpoint shapes, there are two options:
      # 1. We receive the sessions as a hash where the keys are session IDs. We can treat this as an array, for now,
      #    since we have no use for a hash-based lookup at this point.  This is the shape in the
      #    /agents/sessions/resources endpoint.
      # 2. We recieve an array of session objects directly. This is the shape in the /agents/resource endpoint.
      sessions = raw_resource["sessions"]
      sessions = sessions.values if sessions.respond_to?(:values)

      PartialAgentSession.from_raw(sessions)
    end

    sig { returns(T.any(Promise[T.nilable(PullRequest)], Promise[NilClass])) }
    def async_resource
      # Ensure the resource is a pull request and that we have an ID to load.
      return Promise.resolve(nil) unless pr?

      # Using a loader here should avoid N+1 queries while fetching resources across AgentSession instances.
      Platform::Loaders::ActiveRecord.load(::PullRequest, resource_id)
    end

    private

    sig { returns(T::Boolean) }
    def pr?
      resource_type == "pull"
    end
  end
end
