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
      when "/programmatic_access_grant"
        handle_programmatic_access_grant(request)
      when "/add_org_member"
        handle_add_org_member(request)
      when "/start_services"
        handle_start_services(request)
      when "/export_env"
        handle_export_env(request)
      when "/integration_installation"
        handle_integration_installation(request)
      when "/scoped_integration_installation"
        handle_scoped_integration_installation(request)
      when "/enable_feature_flag"
        handle_enable_feature_flag(request)
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

    # Handle the /programmatic_access_grant endpoint for minting a fine-grained PAT (PATv2) with a grant.
    #
    # This wraps the ApiProgrammaticGrantHelpers#make_user_programmatic_access_with_grant test helper so that Go
    # integration tests can authenticate as a PATv2 against authenticated endpoints (e.g. GET /stores_alpha/{id}).
    # It creates the access + grant and returns the plaintext token, which callers send as `Authorization: Token <token>`.
    #
    # Request body (JSON):
    #   requester_id / requester_login    - The User who owns the PAT (creates a User if neither is provided).
    #   target_id / target_login          - The User or Organization the PAT targets (default: requester).
    #   permissions                       - Hash of resource => access level, e.g. { "stores" => "read" }.
    #   repository_selection              - One of "none", "all", "subset" (default: "none").
    #   add_requester_as_admin            - When true and target is an Organization, adds the requester as an admin
    #                                       of the target first so the grant can be self-approved (default: false).
    #
    # Response body (JSON): { token:, access_id:, requester_id:, target_id: }
    sig { params(request: Rack::Request).returns(T::Array[T.untyped]) }
    def handle_programmatic_access_grant(request)
      unless request.post?
        return error_response(405, "Method not allowed")
      end

      begin
        params = JSON.parse(request.body.read)
      rescue JSON::ParserError => e
        return error_response(400, "Invalid JSON: #{e.message}")
      end

      begin
        requester = resolve_user(params["requester_id"], params["requester_login"])
        target = resolve_user(params["target_id"], params["target_login"]) || requester

        if params["add_requester_as_admin"] && requester && target&.organization?
          target.add_admin(requester)
        end

        options = { repository_selection: (params["repository_selection"] || "none").to_sym }
        options[:requester] = requester if requester
        options[:target] = target if target
        options[:permissions] = params["permissions"] if params["permissions"]

        access = programmatic_grant_helper.make_user_programmatic_access_with_grant(options)

        token_result = ProgrammaticAccessTokens.domain.generate(
          access.user_id, access.id, expires_at: access.expires_at || 30.days.from_now
        )

        unless token_result.success?
          return error_response(500, "Failed to generate token: #{token_result.error}")
        end

        response_body = {
          token: token_result.value,
          access_id: access.id,
          requester_id: access.user_id,
          target_id: target&.id,
        }.to_json

        [200, { "Content-Type" => "application/json" }, [response_body]]
      rescue ActiveRecord::RecordNotFound => e
        error_response(404, e.message)
      rescue StandardError => e
        Rails.logger.error("Failed to create programmatic access grant: #{e.class} - #{e.message}\n#{e.backtrace&.join("\n")}")
        error_response(500, "Failed to create programmatic access grant: #{e.message}")
      end
    end

    # Resolve a User by id (preferred) or login. Returns nil when neither is provided.
    sig { params(id: T.untyped, login: T.untyped).returns(T.untyped) }
    def resolve_user(id, login)
      return User.find(id.to_i) if id
      return User.find_by!(login: login) if login.present?
      nil
    end

    # Build an object that exposes the ApiProgrammaticGrantHelpers test helper methods.
    sig { returns(T.untyped) }
    def programmatic_grant_helper
      require "test_helpers/api_programmatic_grant_helpers"
      Object.new.extend(ApiProgrammaticGrantHelpers)
    end

    # Handle the /integration_installation endpoint for creating a GitHub App installation with a token.
    #
    # This wraps the make_integration_installation test helper so that Go integration tests can
    # authenticate as a GitHub App (server-to-server) against authenticated endpoints.
    # It creates the integration, sets permissions, installs it on the target, and returns
    # a plaintext installation access token.
    #
    # Request body (JSON):
    #   target_id / target_login          - The Organization (or User) to install the app on (required).
    #   permissions                       - Hash of resource => access level, e.g. { "stores" => "admin" }.
    #   repository_selection              - One of "none", "all", "subset" (default: "none").
    #
    # Response body (JSON): { token:, installation_id:, integration_id:, target_id: }
    sig { params(request: Rack::Request).returns(T::Array[T.untyped]) }
    def handle_integration_installation(request)
      unless request.post?
        return error_response(405, "Method not allowed")
      end

      begin
        params = JSON.parse(request.body.read)
      rescue JSON::ParserError => e
        return error_response(400, "Invalid JSON: #{e.message}")
      end

      begin
        require "test_helpers/machinist_helpers"

        target = resolve_user(params["target_id"], params["target_login"])
        if target.nil?
          return error_response(400, "target_id or target_login is required")
        end

        permissions = (params["permissions"] || {}).transform_values(&:to_sym)

        helper = T.cast(Object.new.extend(GitHub::MachinistHelpers), GitHub::MachinistHelpers)
        installation = helper.make_integration_installation(
          target: target,
          permissions: permissions
        )

        _, token = installation.generate_token.value

        response_body = {
          token: token,
          installation_id: installation.id,
          integration_id: installation.integration_id,
          target_id: target.id,
        }.to_json

        [200, { "Content-Type" => "application/json" }, [response_body]]
      rescue ActiveRecord::RecordNotFound => e
        error_response(404, e.message)
      rescue StandardError => e
        Rails.logger.error("Failed to create integration installation: #{e.class} - #{e.message}\n#{e.backtrace&.join("\n")}")
        error_response(500, "Failed to create integration installation: #{e.message}")
      end
    end

    # Handle the /scoped_integration_installation endpoint for creating a scoped GitHub App installation with a token.
    #
    # This wraps make_scoped_integration_installation so that Go integration tests can authenticate
    # as a scoped GitHub App (server-to-server) against authenticated endpoints.
    # It takes an existing parent installation and creates a scoped installation from it.
    #
    # Request body (JSON):
    #   parent_installation_id    - The ID of the parent IntegrationInstallation (required).
    #
    # Response body (JSON): { token:, installation_id:, parent_installation_id: }
    sig { params(request: Rack::Request).returns(T::Array[T.untyped]) }
    def handle_scoped_integration_installation(request)
      unless request.post?
        return error_response(405, "Method not allowed")
      end

      begin
        params = JSON.parse(request.body.read)
      rescue JSON::ParserError => e
        return error_response(400, "Invalid JSON: #{e.message}")
      end

      begin
        require "test_helpers/machinist_helpers"

        parent_id = params["parent_installation_id"]
        if parent_id.nil?
          return error_response(400, "parent_installation_id is required")
        end

        parent = IntegrationInstallation.find(parent_id.to_i)

        store = nil
        if params["store_id"]
          store = Stores.domain.by_id(params["store_id"])
          if store.nil?
            return error_response(400, "store_id does not reference a valid Store")
          end
        end

        result = ScopedIntegrationInstallation::Creator.perform(
          parent,
          store: store,
          permissions: {},
          entry_point: :test_case
        )

        if result.failed?
          return error_response(500, "Failed to create scoped installation: #{result.error}")
        end
        scoped = result.installation

        token_result = scoped.generate_token
        unless token_result.value
          return error_response(500, "Failed to generate scoped installation token: #{token_result.error}")
        end
        _, token = token_result.value

        response_body = {
          token: token,
          installation_id: scoped.id,
          parent_installation_id: parent.id,
        }.to_json

        [200, { "Content-Type" => "application/json" }, [response_body]]
      rescue ActiveRecord::RecordNotFound => e
        error_response(404, e.message)
      rescue StandardError => e
        Rails.logger.error("Failed to create scoped integration installation: #{e.class} - #{e.message}\n#{e.backtrace&.join("\n")}")
        error_response(500, "Failed to create scoped integration installation: #{e.message}")
      end
    end

    # Handle the /enable_feature_flag endpoint for enabling a feature flag in the test environment.
    #
    # This wraps the enable_feature_flag test helper so that Go integration tests can
    # enable feature flags that gate functionality in the Rails monolith (e.g. allow_stores_fine_grained_resources).
    #
    # Request body (JSON):
    #   name      - The feature flag name (required).
    #
    # Response body (JSON): { success:, name: }
    sig { params(request: Rack::Request).returns(T::Array[T.untyped]) }
    def handle_enable_feature_flag(request)
      unless request.post?
        return error_response(405, "Method not allowed")
      end

      begin
        params = JSON.parse(request.body.read)
      rescue JSON::ParserError => e
        return error_response(400, "Invalid JSON: #{e.message}")
      end

      begin
        name = params["name"]
        if name.nil? || name.empty?
          return error_response(400, "name is required")
        end

        # rubocop:disable GitHub/FeatureManagement/NoVexiManagementUsage
        FeatureFlag.vexi_management.enable_feature_flag(name)
        # rubocop:enable GitHub/FeatureManagement/NoVexiManagementUsage

        response_body = {
          success: true,
          name: name,
        }.to_json

        [200, { "Content-Type" => "application/json" }, [response_body]]
      rescue StandardError => e
        Rails.logger.error("Failed to enable feature flag: #{e.class} - #{e.message}\n#{e.backtrace&.join("\n")}")
        error_response(500, "Failed to enable feature flag: #{e.message}")
      end
    end

    # Handle the /add_org_member endpoint for adding a user to an organization.
    #
    # This wraps Organization#add_member so that Go integration tests can set up org membership
    # (e.g. a non-admin member) before exercising authenticated endpoints.
    #
    # Request body (JSON):
    #   org_id / org_login    - The Organization to add the member to (one is required).
    #   user_id / user_login  - The User to add as a member (one is required).
    #   action                - The membership action/role, e.g. "read" or "admin" (default: "read").
    #
    # Response body (JSON): { success:, org_id:, user_id:, action: }
    sig { params(request: Rack::Request).returns(T::Array[T.untyped]) }
    def handle_add_org_member(request)
      unless request.post?
        return error_response(405, "Method not allowed")
      end

      begin
        params = JSON.parse(request.body.read)
      rescue JSON::ParserError => e
        return error_response(400, "Invalid JSON: #{e.message}")
      end

      begin
        org = resolve_user(params["org_id"], params["org_login"])
        if org.nil? || !org.organization?
          return error_response(400, "org_id or org_login must reference an Organization")
        end

        user = resolve_user(params["user_id"], params["user_login"])
        if user.nil?
          return error_response(400, "user_id or user_login is required")
        end

        action = (params["action"] || "read").to_sym

        org.add_member(user, action: action)

        response_body = {
          success: true,
          org_id: org.id,
          user_id: user.id,
          action: action.to_s,
        }.to_json

        [200, { "Content-Type" => "application/json" }, [response_body]]
      rescue ActiveRecord::RecordNotFound => e
        error_response(404, e.message)
      rescue StandardError => e
        Rails.logger.error("Failed to add org member: #{e.class} - #{e.message}\n#{e.backtrace&.join("\n")}")
        error_response(500, "Failed to add org member: #{e.message}")
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
