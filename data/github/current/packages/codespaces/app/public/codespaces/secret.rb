# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  class Secret
    # Represents "outbound" secrets sent internally from the monolith into the service.
    attr_accessor :name, :encrypted_value, :owner, :type

    VSCS_SECRET_TYPES = [
      TYPE_ENV_VAR               = "EnvironmentVariable",
      TYPE_CONTAINER_REGISTRY    = "ContainerRegistry",
      TYPE_HOST_SETUP            = "HostSetupEnvironmentVariable",
    ]
    VSCS_EMPTY_SECRET_VALUE = " " # Don't use a zero-length string as it'll fail validation on the FE side.
    FILTERED_KEYS = [Codespaces::GetPrebuildSecrets::PREBUILD_PAT_SECRET_KEYS].flatten

    # host_setup: include secrets for host setup scripts run before container creation
    def self.assemble(codespace, host_setup: false)
      if Codespaces::Policy.can_receive_all_secrets?(codespace)
        for_codespace(codespace, host_setup:)
      elsif !Codespaces::Policy.secrets_disabled?
        user_secrets_for_codespace(codespace, host_setup:)
      else
        # If we get to this point, the secrets killswitch is enabled and we are not sending any encrypted values into any codespaces.
        []
      end
    end

    def self.for_prebuild(repository:)
      repo_secrets, org_secrets = repo_org_secrets_for_repository(repository, actor: repository)

      consolidate_secrets([], repo_secrets, org_secrets)
    end

    # Disallows prebuild use if org or repo secrets exist and codespace owner has read only access to repo
    def self.prebuild_allowed?(codespace:)
      return false unless Codespaces::Prebuilds.configured?(codespace.repository)

      return true if !GitHub.flipper[:codespaces_prebuilds_readyonly_access_check].enabled?(codespace.repository) || for_prebuild(repository: codespace.repository).blank?

      Codespaces::Policy.can_receive_all_secrets?(codespace)
    end

    def self.hydrate_secret(name:, owner:, actor:, app:, type: TYPE_ENV_VAR)
      result = Secrets.fetch(
        name:,
        app:,
        owner:,
        actor:,
        include_value: true,
      )

      if block_given?
        filter_result = yield result.credential
        if !filter_result
          return nil
        end
      end

      new(result.credential.name, result.credential.value, owner, type)
    end

    def initialize(name, encrypted_value, owner, type = TYPE_ENV_VAR)
      @name = name
      @encrypted_value = encrypted_value
      @owner = owner

      raise ArgumentError, "Invalid secret type" unless VSCS_SECRET_TYPES.include?(type)
      @type = type
    end

    def to_decrypted_h
      { type:, name:, value: decrypt.presence || VSCS_EMPTY_SECRET_VALUE }
    end

    # This be called as close to sending the payload to VSCS as possible to
    # avoid secret leaking through implicit logging or stacktrace collection
    #
    # We always try decrypting the secret with the next_global_id
    # scope of the owner and return the result of the same. This is done
    # as part of the GlobalID migration that happens in Launch.
    #
    # Tracking issue => https://github.com/github/Actions-India/issues/169
    def decrypt
      encryption_key = if type == TYPE_HOST_SETUP
        Platform::EncryptionKeys::CODESPACES_VM_SECRETS
      else
        Platform::EncryptionKeys::CODESPACES_SECRETS
      end
      decoded = Base64.strict_decode64(encrypted_value)
      DietEarthsmoke::Key.new(encryption_key).open(decoded, scope: owner.next_global_id)
    end

    class << self
      private

      def for_codespace(codespace, host_setup:)
        user_secrets = user_secrets_for_codespace(codespace, host_setup:)

        repo_secrets, org_secrets = repo_org_secrets_for_repository(codespace.repository, actor: codespace.owner)

        secrets, filtered_secrets = consolidate_secrets(user_secrets, repo_secrets, org_secrets)
        secrets
      end

      def user_secrets_for_codespace(codespace, host_setup:)
        app = codespaces_app # Can't memoize these queries in singleton
        secrets = Secrets.for_app(app, owner: codespace.owner, actor: codespace.owner).filter_map do |secret|
          hydrate_secret(name: secret.name, owner: codespace.owner, actor: codespace.owner, app:) do |s|
            secret_is_accessible_to_repo?(s, codespace.repository)
          end
        end

        if host_setup && codespace.billable_owner.in_codespaces_salus_beta? && codespace.billable_owner.feature_enabled?(:codespaces_host_setup_policy)
          secrets += for_host_setup(repository: codespace.repository, billable_owner: codespace.billable_owner, user: codespace.owner)
        end

        secrets
      end

      def for_host_setup(repository:, billable_owner:, user:)
        app = vm_secrets_app # Can't memoize these queries in singleton
        Secrets.for_app(app, owner: billable_owner, actor: user).filter_map do |secret|
          hydrate_secret(name: secret.name, owner: billable_owner, actor: user, app:, type: TYPE_HOST_SETUP)
        end
      end

      def repo_org_secrets_for_repository(repository, actor:)
        repo_secrets, org_secrets = secrets_for_repository(repository, actor: actor, app: codespaces_app)

        [
          # Repository secrets
          repo_secrets.map do |s|
            new(s[:name], s[:value], repository)
          end,

          # Org secrets
          if repository.owner.organization?
            org_secrets.map do |s|
              new(s[:name], s[:value], repository.owner)
            end
          else
            []
          end
        ]
      end

      def secrets_for_repository(repository, actor:, app:)
        Secrets.for_repository(repository, actor: actor, app: app, include_value: true).
                values_at(:repository_secrets, :organization_secrets)
      end

      def consolidate_secrets(user_secrets, repo_secrets, org_secrets)
        secrets = user_secrets
        filtered_secrets = []
        repo_secrets.each do |s|
          if FILTERED_KEYS.include?(s.name)
            filtered_secrets.push(s) unless filtered_secrets.map(&:name).include?(s.name)
            next
          end
          secrets.push(s) unless secrets.map(&:name).include?(s.name)
        end
        org_secrets.each do |s|
          if FILTERED_KEYS.include?(s.name)
            filtered_secrets.push(s) unless filtered_secrets.map(&:name).include?(s.name)
            next
          end
          secrets.push(s) unless secrets.map(&:name).include?(s.name)
        end
        [secrets, filtered_secrets]
      end

      def extract_secrets(secrets, owner:, actor:)
        app = codespaces_app # Can't memoize these queries in singleton
        secrets.map do |s|
          hydrate_secret(name: s[:name], owner: owner, actor: actor, app:)
        end
      end

      def secret_is_accessible_to_repo?(secret, repository)
        # `global_relay_id` is the id that is used to identify entities in
        # graphql. It is how credz identifies things that are owned by the
        # monolith. Here, we're checking if the given repository is selected
        # for this secret.
        #
        # We also check this against the repository's next_global_id since credz
        # will always start returning the next_global_id after the GlobalID migration.
        selected_repository_ids = secret.selected_repositories.map(&:global_id)

        selected_repository_ids.include?(repository.global_relay_id) ||
        selected_repository_ids.include?(repository.next_global_id)
      end

      def codespaces_app
        ::Apps::Internal.integration(:codespaces_production)
      end

      def vm_secrets_app
        ::Apps::Internal.integration(:codespaces_vm_secrets)
      end
    end
  end
end
