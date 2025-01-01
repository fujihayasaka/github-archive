# typed: strict
# frozen_string_literal: true

module GitHub
  module KredzClient
    module Varz
      include Instrumentation::Model
      extend T::Helpers

      class Validation

        sig { returns(T::Boolean) }
        attr_reader :succeeded

        sig { returns(T.nilable(String)) }
        attr_reader :error

        sig { params(succeded: T::Boolean, error: T.nilable(String)).void }
        def initialize(succeded, error)
          @succeeded = succeded
          @error = error
        end

        sig { returns(T::Boolean) }
        def succeeded?
          succeeded
        end

        sig { params(other: Validation).returns(T::Boolean) }
        def ==(other)
          other.succeeded == succeeded &&
            other.error == error
        end
      end

      VARIABLE_VALUE_MAX_SIZE = 48_000
      VARIABLE_VALUE_MAX_SIZE_MESSAGE = "Value is too large."
      VARIABLE_KEY_VALUE_NOT_SET = "Failed to add variable. The variable key and value are empty."
      VARIABLE_KEY_MAX_SIZE = 300
      VARIABLE_KEY_MAX_SIZE_MESSAGE = T.let("Variable key maximum size is #{VARIABLE_KEY_MAX_SIZE} characters.", String)
      VARIABLE_KEY_RESERVED_PREFIX = "GITHUB_"
      VARIABLE_KEY_RESERVED_PREFIX_MESSAGE = "Variable names must not start with GITHUB_."
      VARIABLE_KEY_EMPTY_MESSAGE = "Variable name cannot be empty."
      VARIABLE_VALUE_EMPTY_MESSAGE = "Variable value cannot be empty."
      VARIABLE_KEY_VALID_CHAR_REGEX = /\A[A-Za-z_][A-Za-z0-9_]*\z/
      VARIABLE_KEY_VALID_CHAR_REGEX_MESSAGE = "Variable names can only contain alphanumeric characters ([a-z], [A-Z], [0-9]) or underscores (_). Spaces are not allowed. Must start with a letter ([a-z], [A-Z]) or underscores (_)."
      VARIABLE_ORG_MAX = 1_000
      VARIABLE_REPO_MAX = 100
      VARIABLE_ENV_MAX = 100
      MAX_VARIABLES_PER_PAGE = 30
      DEFAULT_VARIABLES_PER_PAGE = 10

      VARIABLE_OWNER_REPOSITORY_TYPE = :REPOSITORY
      VARIABLE_OWNER_USER_TYPE = :USER
      VARIABLE_OWNER_ORGANIZATION_TYPE = :ORGANIZATION
      VARIABLE_OWNER_ENVIRONMENT_TYPE = :ENVIRONMENT

      VALID_VARIABLE_OWNER_TYPES = T.let([
        VARIABLE_OWNER_REPOSITORY_TYPE,
        VARIABLE_OWNER_USER_TYPE,
        VARIABLE_OWNER_ORGANIZATION_TYPE,
        VARIABLE_OWNER_ENVIRONMENT_TYPE
      ].to_set.freeze, T::Set[Symbol])

      VARIABLE_VISIBILITY_OWNER = :VISIBILITY_OWNER
      VARIABLE_VISIBILITY_ALL_REPOS = :VISIBILITY_ALL_REPOSITORIES
      VARIABLE_VISIBILITY_PRIVATE_REPOS = :VISIBILITY_PRIVATE_REPOSITORIES
      VARIABLE_VISIBILITY_SELECTED_REPOS = :VISIBILITY_SELECTED_REPOSITORIES

      VALID_VARIABLE_VISIBILITIES = T.let([
        VARIABLE_VISIBILITY_ALL_REPOS,
        VARIABLE_VISIBILITY_PRIVATE_REPOS,
        VARIABLE_VISIBILITY_SELECTED_REPOS
      ].to_set.freeze, T::Set[Symbol])

      TO_VISIBILITY_MAP = T.let({
        VARIABLE_VISIBILITY_ALL_REPOS => "all",
        VARIABLE_VISIBILITY_PRIVATE_REPOS => "private",
        VARIABLE_VISIBILITY_SELECTED_REPOS => "selected"
      }.freeze, T::Hash[Symbol, String])

      FROM_VISIBILITY_MAP = T.let({
        "all" => VARIABLE_VISIBILITY_ALL_REPOS,
        "private" => VARIABLE_VISIBILITY_PRIVATE_REPOS,
        "selected" => VARIABLE_VISIBILITY_SELECTED_REPOS
      }.freeze, T::Hash[String, Symbol])

      sig do
        params(
          app: T.untyped,
          owner: T.any(Repository, Organization, Environment),
          actor: T.nilable(User),
          key: String
        ).returns(T.untyped) # GitHub::Kredz::Services::Varz::FetchResponse
      end
      def self.fetch_variable(app:, owner:, actor:, key:)
        enforce_service_available!
        enforce_parameters_present!(app, owner, actor, key)

        GitHub.varz.fetch \
          GitHub::Kredz::Services::Varz::FetchRequest.new(
            repository: GitHub::Kredz::Services::Varz::Repository.new(
              global_id: self.owner_next_global_id(owner),
            ),
            variable: GitHub::Kredz::Services::Varz::Variable.new(
              owner: variable_owner_for(owner, always_pass_next_global_id: true),
              integration_global_id: self.owner_next_global_id(app),
              name: key,
            ),
          )
      end

      sig do
        params(
          app: T.untyped,
          repository: Repository,
          actor: T.nilable(User),
          environments: T.untyped,
          include_value: T::Boolean
        ).returns(T.untyped) # GitHub::Kredz::Services::Varz::ListVariablesForRepositoryResponse
      end
      def self.list_repository_variables(app:, repository:, actor:, environments: [], include_value: true)
        enforce_service_available!
        enforce_parameters_present!(app, repository, actor, "bogus_key_to_force_arg_presence_requirement")

        GitHub.varz.list_variables_for_repository \
          GitHub::Kredz::Services::Varz::ListVariablesForRepositoryRequest.new(
            repository: GitHub::Kredz::Services::Varz::RepositoryWithOwner.new(
              repository: GitHub::Kredz::Services::Varz::Repository.new(
                global_id: self.owner_next_global_id(repository),
              ),
              owner: variable_owner_for(
                T.must_because(repository.owner) do
                  "list_variables_for_repository: Repository must have an owner"
                end,
                always_pass_next_global_id: true
              ),
            ),
            environments: environments.map { |env| variable_owner_for(env, always_pass_next_global_id: true) },
            integration_global_id: self.owner_next_global_id(app),
            is_private: repository.private?,
            include_value: include_value,
          )
      end

      sig do
        params(
          app: T.untyped,
          actor: T.nilable(User),
          owners: T.untyped,
          page: Integer,
          per_page: Integer
        ).returns(T.untyped) # GitHub::Kredz::Services::Varz::ListVariablesForOwnersResponse
      end
      def self.list_variables_for_owners(app:, actor:, owners:, page: 0, per_page: 0)
        enforce_service_available!
        enforce_parameters_present!(app, owners[0], actor, "bogus_key_to_force_arg_presence_requirement")

        owners_param = owners.map { |owner| variable_owner_for(owner, always_pass_next_global_id: true) }
        GitHub.varz.list_variables_for_owners \
          GitHub::Kredz::Services::Varz::ListVariablesForOwnersRequest.new(
            owners: owners_param,
            integration_global_id: self.owner_next_global_id(app),
            page: page,
            per_page: per_page,
          )
      end

      sig do
        params(
          app: T.untyped,
          repository: Repository,
          actor: T.nilable(User),
          page: Integer,
          per_page: Integer
        ).returns(T.untyped) # GitHub::Kredz::Services::Varz::ListOrganizationVariablesForRepositoryResponse
      end
      def self.list_org_variables_for_repository(app:, repository:, actor:, page: 0, per_page: 0)
        enforce_service_available!
        enforce_parameters_present!(app, repository, actor, "bogus_key_to_force_arg_presence_requirement")

        GitHub.varz.list_organization_variables_for_repository \
          GitHub::Kredz::Services::Varz::ListOrganizationVariablesForRepositoryRequest.new(
            repository: GitHub::Kredz::Services::Varz::RepositoryWithOwner.new(
              repository: GitHub::Kredz::Services::Varz::Repository.new(
                global_id: self.owner_next_global_id(repository),
              ),
              owner: variable_owner_for(
                T.must_because(repository.owner) do
                  "list_org_variables_for_repository: Repository must have an owner"
                end,
                always_pass_next_global_id: true
              ),
            ),
            integration_global_id: self.owner_next_global_id(app),
            is_private: repository.private?,
            page: page,
            per_page: per_page,
          )
      end

      sig do
        params(
          app: T.untyped,
          owner: T.any(User, Repository, Organization, Environment),
          actor: T.nilable(User),
          page: Integer,
          per_page: Integer
        ).returns(T.untyped) # GitHub::Kredz::Services::Varz::ListRequest
      end
      def self.list_variables(app:, owner:, actor:, page: 0, per_page: 0)
        enforce_service_available!
        enforce_parameters_present!(app, owner, actor, "bogus_key_to_force_arg_presence_requirement")

        GitHub.varz.list \
          GitHub::Kredz::Services::Varz::ListRequest.new(
            owner: variable_owner_for(owner, always_pass_next_global_id: true),
            integration_global_id: self.owner_next_global_id(app),
            include_value: true,
            page: page,
            per_page: per_page,
          )
      end

      sig do
        params(
          app: T.untyped,
          owner_ids: T::Array[String],
          owner_type: T.nilable(Symbol)
        ).returns(T.untyped) # GitHub::Kredz::Services::Varz::VariableCountsResponse
      end
      def self.get_variable_counts(app:, owner_ids:, owner_type:)
        enforce_service_available!
        raise ArgumentError, "app parameter required" unless app.present?
        raise ArgumentError, "owner_ids parameter required" unless owner_ids.present? && owner_ids.length > 0

        unless owner_type && VALID_VARIABLE_OWNER_TYPES.include?(owner_type)
          raise ArgumentError, "valid owner type required"
        end

        GitHub.varz.get_variable_counts \
          GitHub::Kredz::Services::Varz::VariableCountsRequest.new(
            owner_global_ids: owner_ids.first(100),
            owner_type: owner_type.to_s,
            integration_global_id: self.owner_next_global_id(app),
          )
      end

      sig do
        params(
          app: T.untyped,
          owner: T.any(Repository, Organization, Environment),
          actor: T.nilable(User),
          key: String,
          value: String,
          visibility: T.nilable(Symbol),
          selected_repositories: T::Array[String]
        ).returns(T.untyped) # GitHub::Kredz::Services::Varz::StoreResponse
      end
      def self.store_variable(app:, owner:, actor:, key:, value:, visibility: VARIABLE_VISIBILITY_OWNER, selected_repositories: [])
        enforce_service_available!
        enforce_parameters_present!(app, owner, actor, key)
        raise ArgumentError, "value parameter required" unless value.present?

        response = GitHub.varz.store \
          GitHub::Kredz::Services::Varz::StoreRequest.new(
            variable: GitHub::Kredz::Services::Varz::Variable.new(
              owner: variable_owner_for(owner),
              integration_global_id: self.owner_next_global_id(app),
              name: key,
              value: value.to_s,
              visibility: visibility,
              selected_repositories: selected_repositories.map do |repository_id| GitHub::Kredz::Services::Varz::Repository.new(
                global_id: self.build_repo_next_global_id(repository_id)
                )
              end,
            ),
          )

        # Response might contain errors. If so, we return it without
        # instrumenting the event.
        unless response.error.nil?
          return response
        end
        event = response.data.variable.created_at == response.data.variable.updated_at ? "create_#{event_subject(app)}_variable" : "update_#{event_subject(app)}_variable"
        instrument_event(app: app, owner: owner, actor: actor, key: key, event: event, visibility: visibility, updated_value: true)

        response
      end

      sig do
        params(
          app: T.untyped,
          owner: T.any(Repository, Organization, Environment),
          actor: T.nilable(User),
          key: String,
          updated_key: String,
          value: String,
          visibility: T.nilable(Symbol),
          selected_repositories: T::Array[String]
        ).returns(T.untyped) # GitHub::Kredz::Services::Varz::UpdateResponse
      end
      def self.update_variable(app:, owner:, actor:, key:, updated_key:, value: "", visibility: VARIABLE_VISIBILITY_OWNER, selected_repositories: [])
        enforce_service_available!
        enforce_parameters_present!(app, owner, actor, key)
        if !updated_key.present?
          updated_key = key
        end
        response = GitHub.varz.update \
          GitHub::Kredz::Services::Varz::UpdateRequest.new(
            variable: GitHub::Kredz::Services::Varz::Variable.new(
              owner: variable_owner_for(owner),
              integration_global_id: self.owner_next_global_id(app),
              name: key,
              value: value.to_s,
              visibility: visibility || VARIABLE_VISIBILITY_OWNER,
              selected_repositories: selected_repositories.map do |repository_id| GitHub::Kredz::Services::Varz::Repository.new(
                global_id: self.build_repo_next_global_id(repository_id)
                )
              end,
            ),
            updated_name: updated_key,
          )

        if !response.error.nil?
          return response
        end

        event = "update_#{event_subject(app)}_variable"
        instrument_event(app: app, event: event, owner: owner, actor: actor, key: key, visibility: visibility, updated_value: value.present?, updated_key: updated_key)

        response
      end

      sig do
        params(
          app: T.untyped,
          owner: T.any(Repository, Organization, Environment),
          actor: T.nilable(User),
          key: String
        ).returns(T.untyped) # GitHub::Kredz::Services::Varz::DeleteResponse
      end
      def self.delete_variable(app:, owner:, actor:, key:)
        enforce_service_available!
        enforce_parameters_present!(app, owner, actor, key)

        response = GitHub.varz.delete \
          GitHub::Kredz::Services::Varz::DeleteRequest.new(
            repository: GitHub::Kredz::Services::Varz::Repository.new(
              global_id: self.owner_next_global_id(owner),
            ),
            variable: GitHub::Kredz::Services::Varz::Variable.new(
              owner: variable_owner_for(owner, always_pass_next_global_id: true),
              integration_global_id: self.owner_next_global_id(app),
              name: key,
            ),
          )

        if !response.error.nil?
          return response
        end

        instrument_event(app: app, owner: owner, actor: actor, key: key, event: "remove_#{event_subject(app)}_variable")

        response
      end

      sig { void }
      def self.enforce_service_available!
        return if GitHub.varz.present?
        raise LaunchClient::ServiceUnavailable, "varz service is not configured"
      end
      private_class_method :enforce_service_available!

      sig do
        params(
          app: T.untyped,
          owner: T.untyped,
          actor: T.nilable(User),
          key: String
        ).void
      end
      def self.enforce_parameters_present!(app, owner, actor, key)
        raise ArgumentError, "actor parameter required" unless actor.present?
        raise ArgumentError, "app parameter required" unless app.present?
        raise ArgumentError, "owner parameter required" unless owner.present?
        raise ArgumentError, "key parameter required" unless key.present?
      end
      private_class_method :enforce_parameters_present!

      sig { params(app: T.untyped).returns(String) }
      def self.event_subject(app)
        Apps::Privileged.property(:secrets_event_subject, app: app) || "actions"
      end
      private_class_method :event_subject

      sig do
        params(
          app: T.untyped,
          owner: T.any(Repository, Organization, Environment),
          actor: T.nilable(User),
          key: String,
          event: T.untyped,
          visibility: T.nilable(Symbol),
          updated_value: T::Boolean,
          updated_key: T.nilable(String)
        ).returns(T.nilable(T::Array[GitHub::Kredz::Services::Varz::Variable]))
      end
      def self.instrument_event(app:, owner:, actor:, key:, event:, visibility: nil, updated_value: false, updated_key: nil)
        payload = {
          actor: actor,
          key: key,
          updated_value: updated_value,
          updated_key: updated_key,
        }.tap do |p|
          p[:visibility] = TO_VISIBILITY_MAP[visibility] unless visibility.nil?
        end

        unless app&.launch_github_app?
          payload[:integration] = app
        end

        if owner.is_a? Repository
          repo = owner
          payload[:repo] = repo
          payload[:org] = repo.owner if repo.owner.is_a? Organization
        elsif owner.is_a? Organization
          payload[:org] = owner
        elsif owner.is_a? Environment
          environment = owner
          payload[:environment] = environment
          repo = environment.repository
          if repo.present?
            payload[:repo] = repo
            payload[:org] = repo.owner if repo.owner.is_a? Organization
          end
        end

        GitHub.instrument "#{owner.event_prefix}.#{event}", payload
      end
      private_class_method :instrument_event

      sig { params(key: T.nilable(String)).returns(Validation) }
      def self.validate_key(key)
        if key.nil? || key.empty?
          return Validation.new(false, VARIABLE_KEY_EMPTY_MESSAGE)
        end
        unless key =~ VARIABLE_KEY_VALID_CHAR_REGEX
          return Validation.new(false, VARIABLE_KEY_VALID_CHAR_REGEX_MESSAGE)
        end
        if key.length > VARIABLE_KEY_MAX_SIZE
          return Validation.new(false, VARIABLE_KEY_MAX_SIZE_MESSAGE)
        end
        if key.upcase.start_with?(VARIABLE_KEY_RESERVED_PREFIX)
          return Validation.new(false, VARIABLE_KEY_RESERVED_PREFIX_MESSAGE)
        end

        Validation.new(true, "")
      end

      sig { params(value: T.nilable(String)).returns(Validation) }
      def self.validate_value(value)
        if value.nil? || value.empty?
          return Validation.new(false, VARIABLE_VALUE_EMPTY_MESSAGE)
        end
        if value.bytesize > Varz::VARIABLE_VALUE_MAX_SIZE
          return Validation.new(false, VARIABLE_VALUE_MAX_SIZE_MESSAGE)
        end

        Validation.new(true, "")
      end

      sig { params(visibility: T.nilable(Symbol)).returns(Validation) }
      def self.validate_visibility(visibility)
        unless visibility.present? && VALID_VARIABLE_VISIBILITIES.include?(visibility)
          return Validation.new(false, "Unknown visibility.")
        end

        Validation.new(true, "")
      end

      sig { params(key: T.nilable(String), value: T.nilable(String)).returns(Validation) }
      def self.validate_variable(key, value)
        key_validation = self.validate_key(key)
        unless key_validation.succeeded?
          return key_validation
        end

        value_validation = self.validate_value(value)
        unless value_validation.succeeded?
          return value_validation
        end

        Validation.new(true, "")
      end

      sig { params(key: T.nilable(String), value: T.nilable(String)).returns(Validation) }
      def self.validate_new_variable(key, value)
        validation = validate_variable(key, value)
        unless validation.succeeded?
          return Validation.new(false, validation.error)
        end

        Validation.new(true, "")
      end

      sig do
        params(
          key: T.nilable(String),
          value: T.nilable(String),
          visibility: T.nilable(Symbol)
        ).returns(Validation)
      end
      def self.validate_new_org_variable(key, value, visibility)
        visibility_validation = self.validate_visibility(visibility)
        unless visibility_validation.succeeded?
          return visibility_validation
        end

        self.validate_new_variable(key, value)
      end

      sig { params(key: T.nilable(String), value: T.nilable(String), current_user: T.nilable(User)).returns(Validation) }
      def self.validate_update_request(key, value, current_user)
        if key.nil? && value.nil?
          return Validation.new(false, VARIABLE_KEY_VALUE_NOT_SET)
        end

        unless key.nil?
          key_validation = self.validate_key(key)
          unless key_validation.succeeded?
            return key_validation
          end
        end

        unless value.nil?
          value_validation = self.validate_value(value)
          unless value_validation.succeeded?
            return value_validation
          end
        end

        Validation.new(true, "")
      end

      sig do
        params(
          key: T.nilable(String),
          value: T.nilable(String),
          visibility: T.nilable(Symbol),
          current_user: T.nilable(User),
          selected_repository_ids: T.untyped,
        ).returns(Validation)
      end
      def self.validate_org_update_request(key, value, visibility, current_user, selected_repository_ids)
        # If the request is sending an empty data set, we should noop
        if key.nil? && value.nil? && visibility.nil? && selected_repository_ids.nil?
          return Validation.new(false, VARIABLE_KEY_VALUE_NOT_SET)
        end

        unless key.nil?
          key_validation = self.validate_key(key)
          unless key_validation.succeeded?
            return key_validation
          end
        end

        unless value.nil?
          value_validation = self.validate_value(value)
          unless value_validation.succeeded?
            return value_validation
          end
        end

        unless visibility.nil?
          visibility_validation = self.validate_visibility(visibility)
          unless visibility_validation.succeeded?
            return visibility_validation
          end
        end

        Validation.new(true, "")
      end

      sig { params(repo_global_id: String).returns(String) }
      def self.build_repo_next_global_id(repo_global_id)
        if GitHub.enterprise? || Platform::Helpers::GlobalId.next?(repo_global_id)
          return repo_global_id
        end
        parsed = Platform::Helpers::GlobalId.parse(repo_global_id)
        Platform::Helpers::GlobalId.build_next_global_id(parsed.type, parsed.id.to_i)
      end

      sig { params(owner: T.untyped).returns(String) }
      def self.owner_next_global_id(owner)
        GitHub.enterprise? ? owner.global_relay_id : owner.next_global_id
      end

      sig do
        params(
          owner: T.any(Repository, Organization, Environment, User),
          always_pass_next_global_id: T::Boolean
        ).returns(T.nilable(GitHub::Kredz::Services::Varz::VariableOwner))
      end
      def self.variable_owner_for(owner, always_pass_next_global_id: false)
        # Always get the global_relay_id in case of enterprises since we don't need to
        # migrate enterprise scenarios with respect to globalIDs.
        owner_next_global_id = GitHub.enterprise? ? owner.global_relay_id : owner.next_global_id
        owner_global_id = always_pass_next_global_id ? owner_next_global_id : owner.global_relay_id

        if owner.is_a? Repository
          GitHub::Kredz::Services::Varz::VariableOwner.new(
            repository: GitHub::Kredz::Services::Varz::Repository.new(
              global_id: owner_next_global_id
            ),
          )
        elsif owner.is_a? Organization
          GitHub::Kredz::Services::Varz::VariableOwner.new(
            organization: GitHub::Kredz::Services::Varz::Organization.new(
              global_id: owner_next_global_id
            ),
          )
        elsif owner.is_a? User
          GitHub::Kredz::Services::Varz::VariableOwner.new(
            user: GitHub::Kredz::Services::Varz::User.new(
              global_id: owner_next_global_id
            ),
          )
        elsif owner.is_a? Environment
          GitHub::Kredz::Services::Varz::VariableOwner.new(
            environment: GitHub::Kredz::Services::Varz::Environment.new(
              global_id: owner_next_global_id
            ),
          )
        end
      end
      private_class_method :variable_owner_for
    end
  end
end
