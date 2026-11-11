# typed: strict
# frozen_string_literal: true

module Loops
  # A client for communicating with the Loops service.
  # Handles all HTTP communication and provides a clean interface for Loops operations.
  class Client

    SERVICE_NAME = "loops"
    GRAPHQL_TIMEOUT_SECONDS = 10

    sig { params(user: User, loops_token: T.nilable(String), copilot_token: T.nilable(String)).void }
    def initialize(user:, loops_token: nil, copilot_token: nil)
      @user = user
      @loops_token = loops_token
      @copilot_token = copilot_token
    end

    # Loop operations

    sig { returns(Faraday::Response) }
    def list_loops
      connection.get("/v1/loops")
    end

    sig { params(loop_id: String, version_constraint: String).returns(Faraday::Response) }
    def get_loop(loop_id:, version_constraint:)
      res = connection.get("/v1/loops/#{url_encode(loop_id)}/v/#{url_encode(version_constraint)}")
      if FeatureFlag.vexi.enabled?(:loops_abuse_prevention, @user, default: false) && res.status == 200
        response_loop = JSON.parse(res.body).with_indifferent_access
        owner_login = response_loop[:ownerLogin]
        if owner_login != @user.display_login
          owner = User.find_by_login(owner_login)
          raise SpammyOwnerError if owner.nil? || owner.spammy?
        end
      end
      res
    end

    # Public: Higher level convenience that returns a Loops::Loop PORO or nil.
    # - Does NOT raise on non-200; simply returns nil.
    # - Centralizing JSON -> PORO mapping here keeps GraphQL object types thin
    #   and allows future non-GraphQL callers (REST, background jobs) to reuse
    #   the same parsing/normalization logic.
    #
    # loop_id - [String] stable identifier (UUID) of the loop
    # version_constraint - [String] version constraint (e.g. "0.0.0" for latest)
    #
    # Returns a Loops::Loop or nil if not found or on error.
    sig { params(loop_id: String, version_constraint: String).returns(T.nilable(Loops::Loop)) }
    def fetch_loop(loop_id:, version_constraint:)
      response = get_loop(loop_id: loop_id, version_constraint: version_constraint)
      return nil unless response.success?
      begin
        to_loop_poro(raw_json: response.body)
      rescue StandardError
        nil
      end
    end

    sig { params(loop_data: T::Hash[T.untyped, T.untyped]).returns(Faraday::Response) }
    def create_loop(loop_data:)
      forbid_suspended_user
      response = connection.post("/v1/loops", loop_data.to_json)
      if response.success?
        loop_poro = build_loop_from_create_or_update(loop_data: loop_data, response: response)
        instrument_user_generated_content("loop.create", loop_poro) unless loop_poro.nil?
      end
      response
    end

    sig { params(loop_id: String, version: String, loop_data: T::Hash[T.untyped, T.untyped]).returns(Faraday::Response) }
    def update_loop(loop_id:, version:, loop_data:)
      forbid_suspended_user
      response = connection.post("/v1/loops/#{url_encode(loop_id)}/v/#{url_encode(version)}", loop_data.to_json)
      if response.success?
        loop_poro = build_loop_from_create_or_update(loop_data: loop_data.merge(id: loop_id), response: response)
        instrument_user_generated_content("loop.update", loop_poro) unless loop_poro.nil?
      end
      response
    end

    sig { params(loop_id: String).returns(Faraday::Response) }
    def delete_loop(loop_id:)
      forbid_suspended_user
      connection.delete("/v1/loops/#{url_encode(loop_id)}")
    end

    sig { params(loop_id: String).returns(Faraday::Response) }
    def share_loop(loop_id:)
      forbid_suspended_user
      connection.post("/v1/loops/#{url_encode(loop_id)}/share")
    end

    sig { params(loop_id: String).returns(Faraday::Response) }
    def unshare_loop(loop_id:)
      forbid_suspended_user
      connection.delete("/v1/loops/#{url_encode(loop_id)}/share")
    end

    # Version operations

    sig { params(loop_id: String).returns(Faraday::Response) }
    def list_loop_versions(loop_id:)
      connection.get("/v1/loops/#{url_encode(loop_id)}/versions")
    end

    # Execution operations

    sig { params(loop_id: String, version: String, execution_init: T::Hash[T.untyped, T.untyped]).returns(Faraday::Response) }
    def create_execution(loop_id:, version:, execution_init:)
      forbid_suspended_user
      connection.post("/v1/loops/#{url_encode(loop_id)}/v/#{url_encode(version)}/executions", execution_init.to_json)
    end

    sig { params(loop_id: String, version: String, execution_id: String).returns(Faraday::Response) }
    def get_execution(loop_id:, version:, execution_id:)
      connection.get("/v1/loops/#{url_encode(loop_id)}/v/#{url_encode(version)}/executions/#{url_encode(execution_id)}")
    end

    sig { params(loop_id: String, version: String, execution_id: String, node_id: String, node_execution: T::Hash[T.untyped, T.untyped]).returns(Faraday::Response) }
    def update_node_execution(loop_id:, version:, execution_id:, node_id:, node_execution:)
      forbid_suspended_user
      connection.put("/v1/loops/#{url_encode(loop_id)}/v/#{url_encode(version)}/executions/#{url_encode(execution_id)}/nodes/#{url_encode(node_id)}", node_execution.to_json)
    end

    sig { params(loop_id: String, version: String, execution_id: String, node_id: String, resources: T::Array[T::Hash[T.untyped, T.untyped]]).returns(Faraday::Response) }
    def update_node_execution_resources(loop_id:, version:, execution_id:, node_id:, resources:)
      forbid_suspended_user
      connection.put("/v1/loops/#{url_encode(loop_id)}/v/#{url_encode(version)}/executions/#{url_encode(execution_id)}/nodes/#{url_encode(node_id)}/resources", resources.to_json)
    end

    sig { params(query: String, loop_id: String, version: String, execution_id: String, node_id: String).returns(Faraday::Response) }
    def execute_graphql(query:, loop_id:, version:, execution_id:, node_id:)
      forbid_suspended_user

      request_body = {
        query: query,
        loop_id: loop_id,
        version: version,
        execution_id: execution_id,
        node_id: node_id
      }

      graphql_connection.post("/v1/loops/graphql/execute", request_body.to_json)
    rescue Faraday::TimeoutError
      # Return a 400 Bad Request since this is a user-supplied query
      Faraday::Response.new(
        status: 400,
        response_headers: { "content-type" => "application/json" },
        body: { error: "Your query timed out after #{GRAPHQL_TIMEOUT_SECONDS} seconds. Please simplify your query and try again." }.to_json
      )
    end

    private

    sig { params(event: String, loop_obj: Loops::Loop).void }
    def instrument_user_generated_content(event, loop_obj)
      return unless FeatureFlag.vexi.enabled?(:loops_abuse_prevention, @user, default: false)
      GlobalInstrumenter.instrument(event, {
        actor: @user,
        loop: loop_obj,
      })
    end

    sig { params(loop_data: T::Hash[T.untyped, T.untyped], response: Faraday::Response).returns(T.nilable(Loops::Loop)) }
    def build_loop_from_create_or_update(loop_data:, response:)
      # Merge server body for authoritative fields (id, version, timestamps, etc.)
      server_hash = begin
        raw = JSON.parse(response.body)
        raw.is_a?(Hash) ? raw.deep_symbolize_keys : {}
      rescue StandardError
        {}
      end
      merged = loop_data.deep_symbolize_keys.merge(server_hash) { |_k, old_v, new_v| new_v.nil? ? old_v : new_v }
      to_loop_poro(raw_json: merged.to_json)
    end

    sig { params(raw_json: String).returns(T.nilable(Loops::Loop)) }
    def to_loop_poro(raw_json:)
      data = JSON.parse(raw_json)
      data = data.with_indifferent_access

      owner_login = data[:ownerLogin]
      return nil if owner_login.nil?

      owner = User.find_by_login(owner_login)
      return nil if owner.nil?

      Loops::Loop.new(
        uuid: data[:id],
        owner_id: owner.id,
        owner_login: owner.display_login,
        title: data[:title],
        description: data[:description],
        share_id: data[:shareID],
        version: data[:version],
        updated_at: data[:updatedAt].nil? ? nil : Time.at(data[:updatedAt] / 1000.0).utc,
        visibility: data[:visibility],
        nodes: (data[:nodes].is_a?(Array) ? T.unsafe(data[:nodes]) : nil)
      )
    end

    sig { params(value: String).returns(String) }
    def url_encode(value)
      ERB::Util.url_encode(value)
    end

    sig { returns(Faraday::Connection) }
    def connection
      @connection ||= T.let(build_connection, T.nilable(Faraday::Connection))
    end

    sig { returns(Faraday::Connection) }
    def graphql_connection
      @graphql_connection ||= T.let(build_connection(timeout: GRAPHQL_TIMEOUT_SECONDS), T.nilable(Faraday::Connection))
    end

    sig { params(timeout: Integer).returns(Faraday::Connection) }
    def build_connection(timeout: 5)
      GitHub::FaradayClient.internal(SERVICE_NAME, GitHub.loops_url) do |conn|
        conn.options[:open_timeout] = 10
        conn.options[:timeout] = timeout

        conn.headers["X-GitHub-User-ID"] = @user.id.to_s
        conn.headers["X-GitHub-User-Login"] = @user.display_login
        conn.headers["Content-Type"] = "application/json"

        conn.headers["X-GitHub-Loops-Token"] = @loops_token if @loops_token.present?
        conn.headers["X-Copilot-Api-Token"] = @copilot_token if @copilot_token.present?
      end
    end

    sig { returns(NilClass) }
    def forbid_suspended_user
      raise SuspendedUserError.new if @user.suspended? && FeatureFlag.vexi.enabled?(:loops_abuse_prevention, @user, default: false)
    end

    # TODO: Once we have service-to-service communication in place to
    # fetch dotcom data from the loops service, this abuse-prevention
    # error handling should be moved to the loops service.
    class SuspendedUserError < StandardError
    end

    class SpammyOwnerError < StandardError
    end
  end
end
