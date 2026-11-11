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
      else
        error_response(404, "Endpoint not found")
      end
    rescue StandardError => e
      error_response(500, "Unexpected error: #{e.message}")
    end

    private

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
