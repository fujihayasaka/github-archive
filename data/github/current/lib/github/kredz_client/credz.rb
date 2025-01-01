# typed: true
# frozen_string_literal: true

module GitHub
  module KredzClient
    module Credz

      include Instrumentation::Model

      class Validation
        attr_reader :succeeded, :error

        def initialize(succeded, error)
          @succeeded = succeded
          @error = error
        end

        def succeeded?
          succeeded
        end

        def ==(other)
          other.succeeded == succeeded &&
            other.error == error
        end
      end

      SECRET_VALUE_MAX_SIZE = 64_000
      SECRET_VALUE_MAX_SIZE_MESSAGE = "Value is too large."
      SECRET_KEY_MAX_SIZE = 300
      SECRET_KEY_MAX_SIZE_MESSAGE = "Secret key maximum size is #{SECRET_KEY_MAX_SIZE} characters."
      SECRET_KEY_RESERVED_PREFIX = "GITHUB_"
      SECRET_KEY_RESERVED_PREFIX_MESSAGE = "Secret names must not start with GITHUB_."
      SECRET_KEY_VALID_CHAR_REGEX = /\A[A-Za-z_][A-Za-z0-9_]*\z/
      SECRET_KEY_VALID_CHAR_REGEX_MESSAGE = "Secret names can only contain alphanumeric characters ([a-z], [A-Z], [0-9]) or underscores (_). Spaces are not allowed. Must start with a letter ([a-z], [A-Z]) or underscores (_)."
      SECRET_UNKNOWN_VISIBILITY_MESSAGE = "Unknown visibility."
      SECRET_ORG_MAX = 1_000
      SECRET_REPO_MAX = 100
      SECRET_ENV_MAX = 100

      CREDENTIAL_OWNER_REPOSITORY_TYPE = :REPOSITORY
      CREDENTIAL_OWNER_USER_TYPE = :USER
      CREDENTIAL_OWNER_ORGANIZATION_TYPE = :ORGANIZATION
      CREDENTIAL_OWNER_ENVIRONMENT_TYPE = :ENVIRONMENT

      VALID_CREDENTIAL_OWNER_TYPES = [
        CREDENTIAL_OWNER_REPOSITORY_TYPE,
        CREDENTIAL_OWNER_USER_TYPE,
        CREDENTIAL_OWNER_ORGANIZATION_TYPE,
        CREDENTIAL_OWNER_ENVIRONMENT_TYPE
      ].to_set.freeze

      CREDENTIAL_VISIBILITY_OWNER = :VISIBILITY_OWNER
      CREDENTIAL_VISIBILITY_ALL_REPOS = :VISIBILITY_ALL_REPOSITORIES
      CREDENTIAL_VISIBILITY_PRIVATE_REPOS = :VISIBILITY_PRIVATE_REPOSITORIES
      CREDENTIAL_VISIBILITY_SELECTED_REPOS = :VISIBILITY_SELECTED_REPOSITORIES

      VALID_CREDENTIAL_VISIBILITIES = [
        CREDENTIAL_VISIBILITY_ALL_REPOS,
        CREDENTIAL_VISIBILITY_PRIVATE_REPOS,
        CREDENTIAL_VISIBILITY_SELECTED_REPOS
      ].to_set.freeze

      TO_VISIBILITY_MAP = {
        CREDENTIAL_VISIBILITY_ALL_REPOS => "all",
        CREDENTIAL_VISIBILITY_PRIVATE_REPOS => "private",
        CREDENTIAL_VISIBILITY_SELECTED_REPOS => "selected"
      }.freeze

      FROM_VISIBILITY_MAP = {
        "all" => CREDENTIAL_VISIBILITY_ALL_REPOS,
        "private" => CREDENTIAL_VISIBILITY_PRIVATE_REPOS,
        "selected" => CREDENTIAL_VISIBILITY_SELECTED_REPOS
      }.freeze

      def self.list_repository_secrets(app:, repository:, actor:, environments: [], include_value: false)
        enforce_service_available!
        enforce_parameters_present!(app, repository, actor, "bogus_key_to_force_arg_presence_requirement")

        get_kredz_instance.list_secrets_for_repository \
          GitHub::Launch::Services::Credz::ListSecretsForRepositoryRequest.new(
            repository: GitHub::Launch::Services::Credz::RepositoryWithOwner.new(
              repository: GitHub::Launch::Services::Credz::Repository.new(
                global_id: self.owner_next_global_id(repository),
              ),
              owner: credential_owner_for(repository.owner, always_pass_next_global_id: true),
            ),
            environments: environments.map { |env| credential_owner_for(env, always_pass_next_global_id: true) },
            integration: self.owner_next_global_id(app),
            is_private: repository.private?,
            include_value: include_value,
          )
      end

      def self.list_credentials(app:, owner:, actor:)
        enforce_service_available!
        enforce_parameters_present!(app, owner, actor, "bogus_key_to_force_arg_presence_requirement")

        get_kredz_instance.list \
          GitHub::Launch::Services::Credz::ListRequest.new(
            owner: credential_owner_for(owner, always_pass_next_global_id: true),
            integration: self.owner_next_global_id(app),
          )
      end

      def self.fetch_credential(app:, owner:, actor:, key:, include_value:)
        enforce_service_available!
        enforce_parameters_present!(app, owner, actor, key)

        get_kredz_instance.fetch \
          GitHub::Launch::Services::Credz::FetchRequest.new(
            repository: GitHub::Launch::Services::Credz::Repository.new(
              global_id: self.owner_next_global_id(owner),
            ),
            credential: GitHub::Launch::Services::Credz::Credential.new(
              owner: credential_owner_for(owner, always_pass_next_global_id: true),
              integration: self.owner_next_global_id(app),
              name: key,
            ),
            include_value: include_value,
          )
      end

      def self.get_secret_counts(app:, owner_ids:, owner_type:)
        enforce_service_available!
        raise ArgumentError, "app parameter required" unless app.present?
        raise ArgumentError, "owner_ids parameter required" unless owner_ids.present? && owner_ids.length > 0

        unless owner_type && VALID_CREDENTIAL_OWNER_TYPES.include?(owner_type)
          raise ArgumentError, "valid owner type required"
        end

        get_kredz_instance.get_secret_counts \
          GitHub::Launch::Services::Credz::SecretCountsRequest.new(
            owner_global_ids: owner_ids.first(100),
            owner_type: owner_type,
            integration: self.owner_next_global_id(app),
          )
      end

      def self.create_credential(app:, owner:, actor:, key:, value:, visibility: CREDENTIAL_VISIBILITY_OWNER, selected_repositories: [])
        enforce_service_available!
        enforce_parameters_present!(app, owner, actor, key)
        raise ArgumentError, "value parameter required" unless value.present?

        response = get_kredz_instance.create \
          GitHub::Launch::Services::Credz::CreateRequest.new(
            credential: GitHub::Launch::Services::Credz::Credential.new(
              owner: credential_owner_for(owner),
              integration: app.global_relay_id,
              integration_next_global_id: self.owner_next_global_id(app),
              name: key,
              value: value.to_s,
              visibility: visibility,
              selected_repositories: selected_repositories.map do |repository_id| GitHub::Launch::Services::Credz::Repository.new(
                global_id: repository_id,
                new_global_id: self.build_repo_next_global_id(repository_id)
                )
              end,
            ),
            is_encrypted_with_next_global_id_scope: !GitHub.enterprise?
          )

        # Response might contain errors. If so, we return it without
        # instrumenting the event.
        unless response.error.nil?
          return response
        end

        selected_repository_ids = map_repository_ids(selected_repositories)

        event = "create_#{event_subject(app)}_secret"
        instrument_event(app: app, owner: owner, actor: actor, key: key, event: event, visibility: visibility, updated_value: true, selected_repository_ids: selected_repository_ids)

        response
      end

      def self.store_credential(app:, owner:, actor:, key:, value:, visibility: CREDENTIAL_VISIBILITY_OWNER, selected_repositories: [])
        enforce_service_available!
        enforce_parameters_present!(app, owner, actor, key)
        raise ArgumentError, "value parameter required" unless value.present?

        response = get_kredz_instance.store \
          GitHub::Launch::Services::Credz::StoreRequest.new(
            credential: GitHub::Launch::Services::Credz::Credential.new(
              owner: credential_owner_for(owner),
              integration: app.global_relay_id,
              integration_next_global_id: self.owner_next_global_id(app),
              name: key,
              value: value.to_s,
              visibility: visibility,
              selected_repositories: selected_repositories.map do |repository_id| GitHub::Launch::Services::Credz::Repository.new(
                global_id: repository_id,
                new_global_id: self.build_repo_next_global_id(repository_id)
                )
              end,
            ),
            is_encrypted_with_next_global_id_scope: !GitHub.enterprise?
          )

        # Response might contain errors. If so, we return it without
        # instrumenting the event.
        unless response.error.nil?
          return response
        end

        selected_repository_ids = map_repository_ids(selected_repositories)
        event = response.data.credential.created_at == response.data.credential.updated_at ? "create_#{event_subject(app)}_secret" : "update_#{event_subject(app)}_secret"
        instrument_event(app:, owner:, actor:, key:, event:, visibility:, updated_value: true, selected_repository_ids:)

        response
      end

      def self.update_credential(app:, owner:, actor:, key:, value: "", visibility: CREDENTIAL_VISIBILITY_OWNER, selected_repositories: [])
        enforce_service_available!
        enforce_parameters_present!(app, owner, actor, key)

        response = get_kredz_instance.update \
          GitHub::Launch::Services::Credz::UpdateRequest.new(
            credential: GitHub::Launch::Services::Credz::Credential.new(
              owner: credential_owner_for(owner),
              integration: app.global_relay_id,
              integration_next_global_id: self.owner_next_global_id(app),
              name: key,
              value: value.to_s,
              visibility: visibility || CREDENTIAL_VISIBILITY_OWNER,
              selected_repositories: selected_repositories.map do |repository_id| GitHub::Launch::Services::Credz::Repository.new(
                global_id: repository_id,
                new_global_id: self.build_repo_next_global_id(repository_id)
                )
              end,
            ),
            is_encrypted_with_next_global_id_scope: !GitHub.enterprise?
          )

        if !response.error.nil?
          return response
        end

        selected_repository_ids = map_repository_ids(selected_repositories)

        event = "update_#{event_subject(app)}_secret"
        instrument_event(app: app, event: event, owner: owner, actor: actor, key: key, visibility: visibility, updated_value: value.present?, selected_repository_ids: selected_repository_ids)

        response
      end

      def self.delete_credential(app:, owner:, actor:, key:)
        enforce_service_available!
        enforce_parameters_present!(app, owner, actor, key)

        response = get_kredz_instance.delete \
          GitHub::Launch::Services::Credz::DeleteRequest.new(
            repository: GitHub::Launch::Services::Credz::Repository.new(
              global_id: self.owner_next_global_id(owner),
            ),
            credential: GitHub::Launch::Services::Credz::Credential.new(
              owner: credential_owner_for(owner, always_pass_next_global_id: true),
              integration: self.owner_next_global_id(app),
              name: key,
            ),
          )

        if !response.error.nil?
          return response
        end

        instrument_event(app: app, owner: owner, actor: actor, key: key, event: "remove_#{event_subject(app)}_secret")

        response
      end

      def self.get_kredz_instance
        GitHub.kredz
      end
      private_class_method :get_kredz_instance

      def self.enforce_service_available!
        return if get_kredz_instance.present?
        raise LaunchClient::ServiceUnavailable, "credz service is not configured"
      end
      private_class_method :enforce_service_available!

      def self.enforce_parameters_present!(app, owner, actor, key)
        raise ArgumentError, "actor parameter required" unless actor.present?
        raise ArgumentError, "app parameter required" unless app.present?
        raise ArgumentError, "owner parameter required" unless owner.present?
        raise ArgumentError, "key parameter required" unless key.present?
      end
      private_class_method :enforce_parameters_present!

      def self.event_subject(app)
        Apps::Privileged.property(:secrets_event_subject, app: app) || "actions"
      end
      private_class_method :event_subject

      sig { params(global_ids: T::Array[String]).returns(T::Array[Integer]) }
      def self.map_repository_ids(global_ids)
        global_ids.map do |global_id|
          id = Platform::Helpers::NodeIdentification.from_global_id(global_id)[1].to_i
        end
      end
      private_class_method :map_repository_ids

      def self.instrument_event(app:, owner:, actor:, key:, event:, visibility: nil, updated_value: false, selected_repository_ids: [])
        payload = {
          actor: actor,
          key: key,
          updated_value: updated_value,
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
          if visibility == CREDENTIAL_VISIBILITY_SELECTED_REPOS && GitHub.flipper[:kredz_audit_selected_repos].enabled?(owner)
            payload[:selected_repository_ids] = selected_repository_ids
          end
        elsif owner.is_a? Environment
          environment = owner
          payload[:environment] = environment
          repo = environment.repository
          payload[:repo] = repo
          payload[:org] = repo.owner if repo.present? && repo.owner.is_a?(Organization)
        elsif owner.is_a? User
          payload[:scoped_repo_ids] = selected_repository_ids if selected_repository_ids.present?
          payload[:user] = owner
        end

        GitHub.instrument "#{owner.event_prefix}.#{event}", payload
      end
      private_class_method :instrument_event

      def self.validate_secret(key, encrypted_value)
        unless key =~ SECRET_KEY_VALID_CHAR_REGEX
          return Validation.new(false, SECRET_KEY_VALID_CHAR_REGEX_MESSAGE)
        end
        if key.length >= SECRET_KEY_MAX_SIZE
          return Validation.new(false, SECRET_KEY_MAX_SIZE_MESSAGE)
        end
        if key.upcase.start_with?(SECRET_KEY_RESERVED_PREFIX)
          return Validation.new(false, SECRET_KEY_RESERVED_PREFIX_MESSAGE)
        end
        if encrypted_value.bytesize > Credz::SECRET_VALUE_MAX_SIZE
          return Validation.new(false, SECRET_VALUE_MAX_SIZE_MESSAGE)
        end
        Validation.new(true, "")
      end

      def self.validate_org_secret(key, encrypted_value, visibility)
        unless VALID_CREDENTIAL_VISIBILITIES.include?(visibility)
          return Validation.new(false, SECRET_UNKNOWN_VISIBILITY_MESSAGE)
        end

        self.validate_secret(key, encrypted_value)
      end

      def self.build_repo_next_global_id(repo_global_id)
        if GitHub.enterprise? || Platform::Helpers::GlobalId.next?(repo_global_id)
          return repo_global_id
        end
        parsed = Platform::Helpers::GlobalId.parse(repo_global_id)
        Platform::Helpers::GlobalId.build_next_global_id(parsed.type, parsed.id.to_i)
      end

      def self.owner_next_global_id(owner)
        GitHub.enterprise? ? owner.global_relay_id : owner.next_global_id
      end

      def self.credential_owner_for(owner, always_pass_next_global_id: false)
        # Always get the global_relay_id in case of enterprises since we don't need to
        # migrate enterprise scenarios with respect to globalIDs.
        owner_next_global_id = GitHub.enterprise? ? owner.global_relay_id : owner.next_global_id
        owner_global_id = always_pass_next_global_id ? owner_next_global_id : owner.global_relay_id

        if owner.is_a? Repository
          GitHub::Launch::Services::Credz::CredentialOwner.new(
            repository: GitHub::Launch::Services::Credz::Repository.new(
              global_id: owner_global_id,
              new_global_id: owner_next_global_id,
            ),
          )
        elsif owner.is_a? Organization
          GitHub::Launch::Services::Credz::CredentialOwner.new(
            organization: GitHub::Launch::Services::Credz::Organization.new(
              global_id: owner_global_id,
              new_global_id: owner_next_global_id,
            ),
          )
        elsif owner.is_a? User
          GitHub::Launch::Services::Credz::CredentialOwner.new(
            user: GitHub::Launch::Services::Credz::User.new(
              global_id: owner_global_id,
              new_global_id: owner_next_global_id,
            ),
          )
        elsif owner.is_a? Environment
          GitHub::Launch::Services::Credz::CredentialOwner.new(
            environment: GitHub::Launch::Services::Credz::Environment.new(
              global_id: owner_global_id,
              repository_id: T.must(owner.repository).id,
              new_global_id: owner_next_global_id,
            ),
          )
        end
      end
      private_class_method :credential_owner_for
    end
  end
end
