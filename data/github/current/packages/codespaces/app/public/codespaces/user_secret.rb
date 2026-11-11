# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  class UserSecret
    include ActiveModel::Model

    class CreationError < StandardError; end
    class UpdatingError < StandardError; end
    class DeletionError < StandardError; end

    SECRET_REPO_LIMIT = 100 # This is an arbitrary threshold to avoid abuse, we should change this per any real customer feedback!

    attr_accessor :user
    attr_writer   :repository_ids, :selected_repositories_count
    attr_accessor :key_id, :name, :encrypted_value, :created_at, :updated_at, :visibility

    validates :user, :name, presence: true
    validates :name, format: { with: /\A[a-zA-Z0-9_]+\z/, message: "only allows letters, numbers, and underscores" }
    validates :name, exclusion: { in: %w(new), message: "%{value} is reserved." }
    validates :key_id, presence: true, numericality: { only_integer: true }, allow_blank: false
    validates :encrypted_value, presence: true, on: :new
    validate  :key_id_matches_user
    validate  :valid_secret, on: :new
    validate  :has_accessible_repositories, on: :new
    validate  :is_unique, on: :new
    validate  :max_repository_ids

    def self.for(user, app: ::Apps::Privileged.integration(:codespaces_production))
      begin
        result = Secrets.list(
          app: app,
          owner: user,
          actor: user,
        )
      rescue Secrets::Error
        return []
      end

      key_id, _ = Secrets.github_public_key(owner: user, key_name: Platform::EncryptionKeys::CODESPACES_SECRETS)
      result.credentials.map do |cred|
        new(
          user: user,
          name: cred.name,
          key_id: key_id,
          visibility: cred.visibility,
          selected_repositories_count: cred.selected_repositories_count,
          created_at: Secrets.secret_created_at(cred),
          updated_at: Secrets.secret_updated_at(cred)
        )
      end
    end

    def self.for_user_and_name(user, name, app: ::Apps::Privileged.integration(:codespaces_production))
      public_key = ::Secrets.github_public_key(
        owner: user,
        key_name: Platform::EncryptionKeys::CODESPACES_SECRETS
      ).first

      new(
        name: name,
        user: user,
        key_id: public_key
      )
    end

    def selected_repositories_count
      if repository_ids.present?
        selected_repositories.length
      else
        @selected_repositories_count
      end
    end

    def is_unique
      return true unless user&.feature_flag_enabled_or_raise?(:codespaces_better_duplicate_secrets_error) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      # There is one case where updating a secret could lead to this being tested and fail validation
      if @is_updating
        return true
      end
      # Since this validation depends on previous validations, we should not run it if there are any errors
      return false if defined?(@credential) || errors.any?

      begin
        result = Secrets.fetch(
          name: name,
          app: app,
          owner: user,
          actor: user,
        )
      rescue Secrets::Error
        # If it fails, it can be because the secret does not exist
        # or something else is wrong. For the former, we are fine
        # and for the latter, the caller can handle the error.
        return true
      end
      if result.present?
        errors.add(:name, :taken, message: "'#{name}' is already taken.")
        return false
      end
      true
    end

    def repository_ids
      Array(@repository_ids).map!(&:to_i)
    end

    def repositories
      @repositories ||= Codespaces::RepositoryQuery.visible_repos(user, repository_ids)
    end

    def fetch_credential
      return @credential if defined?(@credential)
      return unless valid?

      begin
        result = Secrets.fetch(
          name: name,
          app: app,
          owner: user,
          actor: user,
          include_value: true,
        )
      rescue Secrets::Error
        return nil
      end
      @credential = result&.credential
      if @credential.present?
        # Populate attrs with data from credential once fetched
        @selected_repositories_count = @credential.selected_repositories_count
        @encoded_value = @credential.value
        @visibility = @credential.visibility
        selected_repository_node_ids = @credential.selected_repositories.map(&:global_id).to_set
        @repository_ids = selected_repository_node_ids.map { |global_id| Platform::Helpers::NodeIdentification.from_global_id(global_id)[1].to_i }
        @created_at = Secrets.secret_created_at(@credential)
        @updated_at = Secrets.secret_updated_at(@credential)
      end
      @credential
    end

    def save
      begin
        return false unless valid?(:new)
        result = Secrets.create(
          app: app,
          owner: user,
          actor: user,
          name: name,
          value: encoded_value,
          visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS,
          selected_repositories: selected_repositories,
        )
      rescue Secrets::Error, ArgumentError => e
        error_reporter.report(
          CreationError.new(e.message),
          user: user&.login, # rubocop:disable GitHub/DoNotAllowLogin
          error_msg: "Error creating a user's secret for Codespaces.",
          error_type: e.class.name
        )
      end
      result&.stored
    end

    def update
      begin
        if encrypted_value.present?
          # Reset encoded_value in case of memoization
          # This verifies that the encoded_value is correctly using the new encrypted_value
          @encoded_value = nil
          @is_updating = true
          return false unless valid?(:new)
        else
          # If we are not modifiying the encrypted value we can skip the :new
          # validations and we must pass and empty string to Credz as our
          # encoded_value.
          @encoded_value = ""
          return false unless valid?
        end
        # Resetting so further validations are not affected by this flag
        @is_updating = nil
        result = Secrets.update(
          app: app,
          owner: user,
          actor: user,
          name: name,
          value: encoded_value,
          visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS,
          selected_repositories: selected_repositories
        )
      rescue Secrets::Error, ArgumentError => e
        error_reporter.report(
          UpdatingError.new(e.message),
          user: user&.login, # rubocop:disable GitHub/DoNotAllowLogin
          error_msg: "Error updating a user's secret for Codespaces.",
          error_type: e.class.name
        )
      end
      result&.updated
    end

    def delete
      return false unless valid?

      begin
        result = Secrets.delete(
          name: name,
          app: app,
          owner: user,
          actor: user
        )
      rescue Secrets::Error => e
        error_reporter.report(
          DeletionError.new(e.message),
          user: user&.login, # rubocop:disable GitHub/DoNotAllowLogin
          error_msg: "Error deleting a user's secret for Codespaces.",
          error_type: e.class.name
        )
      end

      result&.success
    end

    private

    def encoded_value
      @encoded_value ||= begin
        Base64.strict_encode64(Secrets.embed(key_id_int, Base64.strict_decode64(encrypted_value)))
      rescue ArgumentError => error
        errors.add(:encrypted_value, :invalid, message: error.message)
        raise error
      end
    end

    # Filter and map repository_ids to their global_relay_ids for consumption by Credz
    def selected_repositories
      return [] unless user

      Codespaces::RepositoryQuery.visible_repos(user, repository_ids).map(&:global_relay_id).sort
    end

    def has_accessible_repositories
      return unless repository_ids.present?

      errors.add(:repository_ids, :invalid, message: "at least one accessible repository must be provided") unless selected_repositories.present?
    end

    def max_repository_ids
      errors.add(:repository_ids, :too_long, count: SECRET_REPO_LIMIT) if repository_ids && repository_ids.length > SECRET_REPO_LIMIT
    end

    def key_id_matches_user
      return unless key_id_int.present? && user.present?
      id, _ = Secrets.github_public_key(owner: user, key_name: Platform::EncryptionKeys::CODESPACES_SECRETS)
      errors.add(:key_id, :invalid, message: "id is invalid") unless key_id_int == id
    end

    def valid_secret
      return unless name.present? && encrypted_value.present?

      validation = GitHub::KredzClient::Credz.validate_secret(name, encrypted_value)
      errors.add(:encrypted_value, :invalid, message: validation.error) unless validation.succeeded?
    end

    def key_id_int
      return @key_id_int if defined?(@key_id_int)

      @key_id_int = Integer(key_id)
    rescue ArgumentError, TypeError
      @key_id_int = nil
    end

    def error_reporter
      @error_reporter ||= Codespaces::ErrorReporter.new
    end

    def app
      @app ||= ::Apps::Privileged.integration(:codespaces_production)
    end
  end
end
