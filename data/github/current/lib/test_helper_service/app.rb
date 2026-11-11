# typed: true
# frozen_string_literal: true

require "rack/request"

module TestHelperService
  # Rack application for the Test Helper Service REST API
  # This service allows remote usage of test fixtures and other helpers.
  class App
    # Public: Rack application handler for the Test Helper Service.
    #
    # env - The Rack environment as a Hash.
    #
    # Returns a Rack response array [status, headers, body].
    sig { params(env: T.untyped).returns(T::Array[T.untyped]) }
    def call(env)
      request = Rack::Request.new(env)

      # Ensure we're in test environment
      unless Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
        return error_response(403, "Service only available in test environment")
      end

      # Route to appropriate handler based on path
      case request.path
      when "/fixtures"
        handle_fixtures(request)
      when "/reset"
        handle_reset(request)
      when "/truncate"
        handle_truncate(request)
      when "/start_services"
        handle_start_services(request)
      when "/export_env"
        handle_export_env(request)
      else
        error_response(404, "Endpoint not found")
      end
    rescue StandardError => e
      error_response(500, "Unexpected error: #{e.message}")
    end

    private

    # Handle the /export_env endpoint for exporting reposd environment variables to a file.
    #
    # This endpoint is needed for the reposd integration CI test because reposd needs to connect
    # to the same test databases that Rails creates. The database names are dynamically generated
    # based on TEST_ENV_NUMBER (e.g., github_test_42_collab) and stored in Rails' ActiveRecord
    # configuration. This endpoint computes those database connection parameters from Rails config
    # and exports them to a file that can be sourced by the CI script.
    #
    # We use this HTTP endpoint (rather than running Ruby directly in CI) to take advantage of the
    # already-running Rails test environment, which is significantly faster than bootstrapping
    # Rails from scratch just to export environment variables.
    sig { params(request: Rack::Request).returns(T::Array[T.untyped]) }
    def handle_export_env(request)
      unless request.get?
        return error_response(405, "Method not allowed")
      end

      begin
        require_relative "../../test/test_helpers/test_services"

        # Get the env_dest parameter from query string
        env_dest = request.params["env_dest"]

        unless env_dest
          return error_response(400, "Missing required parameter: env_dest")
        end

        # Create reposd service instance and call script/reposd-server directly
        reposd = TestServices::Reposd.new
        system(reposd.app_env, "script/reposd-server", "--export-env=#{env_dest}")

        [200, { "Content-Type" => "application/json" }, [{ success: true, path: env_dest }.to_json]]
      rescue StandardError => e
        Rails.logger.error("Failed to export env: #{e.class} - #{e.message}")
        Rails.logger.error(e.backtrace&.join("\n"))
        error_response(500, "Failed to export env: #{e.message}")
      end
    end

    # Handle the /start_services endpoint for starting test services
    sig { params(request: Rack::Request).returns(T::Array[T.untyped]) }
    def handle_start_services(request)
      unless request.post?
        return error_response(405, "Method not allowed")
      end

      begin
        services_pids = TestServices.start

        [200, { "Content-Type" => "application/json" }, [{ success: true, message: "Test services started", pids: services_pids }.to_json]]
      rescue StandardError => e
        Rails.logger.error("Failed to start test services: #{e.class} - #{e.message}")
        error_response(500, "Failed to start test services: #{e.message}")
      end
    end

    # Handle the /reset endpoint for resetting test state
    sig { params(request: Rack::Request).returns(T::Array[T.untyped]) }
    def handle_reset(request)

      unless request.post?
        return error_response(405, "Method not allowed")
      end

      begin
        # Create a test case instance to call reset_everything
        GitHub::BasicTestCase.new("reset").reset_everything

        # Initialize DGit fileservers
        ::DGit.write_seed_data unless GitHub::DGit.get_hosts.any?

        [200, { "Content-Type" => "application/json" }, [{ success: true, message: "Reset completed" }.to_json]]
      rescue StandardError => e
        Rails.logger.error("Failed to reset: #{e.class} - #{e.message}\n#{e.backtrace&.join("\n")}")
        error_response(500, "Failed to reset: #{e.message}")
      end
    end

    # Handle the /truncate endpoint for truncating all database tables
    sig { params(request: Rack::Request).returns(T::Array[T.untyped]) }
    def handle_truncate(request)
      unless request.post?
        return error_response(405, "Method not allowed")
      end

      begin
        # Iterate over all database clusters
        ApplicationRecord.clusters.each do |cluster|
          connection = cluster.connection

          # Get all tables except system tables
          tables = connection.tables - %w[
            schema_migrations
            ar_internal_metadata
          ]

          # Truncate all tables for this cluster
          connection.truncate_tables(*tables) if tables.any?
        end

        [200, { "Content-Type" => "application/json" }, [{ success: true, message: "Databases truncated" }.to_json]]
      rescue StandardError => e
        Rails.logger.error("Failed to truncate: #{e.class} - #{e.message}")
        error_response(500, "Failed to truncate: #{e.message}")
      end
    end

    # Handle the /fixtures endpoint for creating test fixtures
    sig { params(request: Rack::Request).returns(T::Array[T.untyped]) }
    def handle_fixtures(request)
      # Only accept POST requests
      unless request.post?
        return error_response(405, "Method not allowed")
      end

      # Parse request body
      begin
        params = JSON.parse(request.body.read)
      rescue JSON::ParserError => e
        return error_response(400, "Invalid JSON: #{e.message}")
      end

      fixture_type = params["fixture_type"]
      attributes_json = params["attributes"] || params["attributes_json"]

      # Validate fixture type is provided
      if fixture_type.nil? || fixture_type.empty?
        return error_response(400, "fixture_type is required")
      end

      # Parse attributes
      begin
        attributes = parse_attributes(attributes_json)
      rescue ArgumentError => e
        return error_response(400, e.message)
      end

      # Create the fixture
      begin
        fixture = create_factory_bot_fixture(fixture_type, attributes)
      rescue ArgumentError, KeyError => e
        # Don't expose internal details, just indicate the fixture type is invalid
        return error_response(400, "Invalid fixture type or attributes provided")
      rescue StandardError => e
        # Log the actual error for debugging, but return a generic message
        Rails.logger.error("Failed to create fixture '#{fixture_type}': #{e.class} - #{e.message}")
        return error_response(500, "Failed to create fixture: #{e.message}")
      end

      if fixture_type == "repository"
        i = 0
        wait_time_secs = 5
        until fixture.ready_for_writes? || i > wait_time_secs
          i += 1
          sleep 1
        end

        if i > wait_time_secs && !fixture.ready_for_writes?
          return error_response(500, "Repository not ready after: #{i} seconds")
        end
      end

      # Serialize the fixture to JSON
      fixture_json = serialize_fixture(fixture)
      fixture_id = extract_fixture_id(fixture)

      response_body = {
        fixture: JSON.parse(fixture_json),
        id: fixture_id,
      }.to_json

      [200, { "Content-Type" => "application/json" }, [response_body]]
    end

    sig { params(status: Integer, message: String).returns(T::Array[T.untyped]) }
    def error_response(status, message)
      body = { error: message }.to_json
      [status, { "Content-Type" => "application/json" }, [body]]
    end

    sig { params(attributes_json: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
    def parse_attributes(attributes_json)
      return {} if attributes_json.nil?
      return attributes_json.transform_keys(&:to_sym) if attributes_json.is_a?(Hash)
      return {} if attributes_json.empty?

      parsed = JSON.parse(attributes_json)
      unless parsed.is_a?(Hash)
        raise ArgumentError, "attributes must be a JSON object"
      end
      # Convert keys to symbols for FactoryBot
      parsed.transform_keys(&:to_sym)
    rescue JSON::ParserError => e
      raise ArgumentError, "Invalid JSON in attributes: #{e.message}"
    end

    sig { params(fixture_type: String, attributes: T::Hash[Symbol, T.untyped]).returns(T.untyped) }
    def create_factory_bot_fixture(fixture_type, attributes)
      # Convert fixture_type to symbol
      fixture_symbol = fixture_type.to_sym

      # Call FactoryBot.create with the fixture type and attributes
      FactoryBot.create(fixture_symbol, **attributes)
    end

    sig { params(fixture: T.untyped).returns(String) }
    def serialize_fixture(fixture)
      # Try to serialize the fixture as JSON
      # For ActiveRecord models, use as_json to get a hash representation
      if fixture.respond_to?(:as_json)
        fixture.attributes_before_type_cast.to_json
      else
        # For non-standard objects, return a minimal representation
        # Don't use inspect as it may expose sensitive internal details
        {
          class: fixture.class.name,
          id: (fixture.id if fixture.respond_to?(:id)),
        }.compact.to_json
      end
    rescue StandardError => e
      # If serialization fails, return a safe representation
      Rails.logger.error("Failed to serialize fixture: #{e.class} - #{e.message}")
      {
        error: "Failed to serialize fixture",
        class: fixture.class.name,
      }.to_json
    end

    sig { params(fixture: T.untyped).returns(Integer) }
    def extract_fixture_id(fixture)
      # Try to extract an ID if the fixture has one
      return fixture.id.to_i if fixture.respond_to?(:id) && fixture.id.present?
      0 # Return 0 if no ID is available
    end
  end
end
