# typed: true
# frozen_string_literal: true

class ContentAuthorizer::RepoAuthorizer < ContentAuthorizer
  attr_accessor :repo, :owner, :data

  def initialize(actor, operation, data)
    super
    @repo  = data[:repo]  || GitHub::NullRepository.new
    @owner = data[:owner] || @actor
    @data = data[:data]
  end

  def self.valid_operations
    super + [:fork, :fork_select]
  end

  # Public: All of the authorization errors blocking the given actor from
  # creating or modifying a repo. These should be assembled in priority order
  # (from most urgent/important to least) because the API will only return the
  # first error discovered.
  #
  # fail_fast - Bail out after the first failure.
  #
  # Returns an Array of ContentAuthorizationError objects.
  def errors(fail_fast: false)
    @errors ||= ([]).tap do |errors|
      if !actor
        errors << ContentAuthorizationError::AnonymousActor.new
      end

      if verified_email_required_to?(operation)
        if actor.must_verify_email?
          errors << ContentAuthorizationError::EmailVerificationRequired.new
          return errors if fail_fast
        end
      end

      if repo.archived? && operation != :fork && invalid_action_for_archived_repo?
        errors << ContentAuthorizationError::RepoArchived.new
        return errors if fail_fast
      end

      if !in_automated_data_transformation? && repo.locked_on_migration?
        errors << ContentAuthorizationError::RepoLocked.new
      end

      if owner.user? && actor != owner
        errors << ContentAuthorizationError::ActorOwnerMismatch.new
      end

      if actor.user? && actor.ghost?
        errors << ContentAuthorizationError::GhostCantDoThat.new
      end
    end
  end

  private

  def invalid_action_for_archived_repo?
    !(update_on_secret_scanning_settings_for_archived_repo? || unarchiving?)
  end

  # This function identifies if the incoming input data on a update request to the repo API
  # is making updates to the secret scanning settings of the repo, specifically enable/disable
  # the checks ensure that this is only happening on:
  # - a repo that is opted into scanning for archive repos.
  # - that the incoming data only has a single field being updated and it matches the secret scanning one, and rejects
  #   the request if any other fields are being updated on their own or together with the secret scanning setting.
  def update_on_secret_scanning_settings_for_archived_repo?
    return false unless operation == :update
    return false unless data.present?

    return false unless repo.archived?
    return false unless SecretScanning::Features::Repo::TokenScanning.new(repo).feature_available?

    return false unless data.keys.size == 1 && data["security_and_analysis"].present?

    data.dig("security_and_analysis", "secret_scanning", "status")
  end

  def unarchiving?
    return false unless operation == :update
    return false unless data.present?

    parse_bool(data["archived"]) == false
  end

  def parse_bool(value)
    ActiveRecord::Type::Boolean.new.cast(value)
  end
end
