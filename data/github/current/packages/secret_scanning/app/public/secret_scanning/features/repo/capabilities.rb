# typed: strict
# frozen_string_literal: true

module SecretScanning::Features::Repo
  # Repository level capabilities for enablement.
  # Fields are originally used in the RepoSync service within token-scanning-service.
  class Capabilities
    extend T::Sig

    sig { params(repo: Repository).void }
    def initialize(repo)
      @repo = repo
      @token_scanning = T.let(SecretScanning::Features::Repo::TokenScanning.new(@repo), SecretScanning::Features::Repo::TokenScanning)
      @public_scanning = T.let(SecretScanning::Features::Repo::PublicScanning.new(@repo), SecretScanning::Features::Repo::PublicScanning)
      @validity_checks = T.let(SecretScanning::Features::Repo::ValidityChecks.new(@repo), SecretScanning::Features::Repo::ValidityChecks)
      @lower_confidence_patterns = T.let(SecretScanning::Features::Repo::LowerConfidencePatterns.new(@repo), SecretScanning::Features::Repo::LowerConfidencePatterns)
      @generic_secrets = T.let(SecretScanning::Features::Repo::GenericSecrets.new(@repo), SecretScanning::Features::Repo::GenericSecrets)
      @wiki_scanning = T.let(SecretScanning::Features::Repo::WikiScanning.new(@repo), SecretScanning::Features::Repo::WikiScanning)
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_hydro_msg
      owner_scope =
        if @repo.owner&.organization?
          :ORGANIZATION_SCOPE
        elsif @repo.owner&.user?
          :USER_SCOPE
        else
          :UNKNOWN_SCOPE
        end

      {
        repository_id: @repo.id,
        owner_id: @repo.owner_id,
        owner_scope:,
        scannable: scannable?,
        ghas_secret_scanning: ghas_secret_scanning?,
        results_visible: results_visible?,
        validity_checks: validity_checks?,
        lower_confidence_patterns: lower_confidence_patterns?,
        generic_secrets: generic_secrets?,
        wiki_scanning: wiki_scanning?,
      }
    end

    # Determines whether the repository is eligible for scanning by our
    # token-scanning-service. When a repository is scannable, alerts will be
    # persisted.
    # An example where this may be "false" is if the repo is staff disabled.
    # Returns false if the repo has already been deleted.
    sig { returns(T::Boolean) }
    def scannable?
      return false if @repo.deleted?
      @token_scanning.enabled? || @public_scanning.enabled?
    end

    # Should any alerts for the scan be made available to repo administrators?
    # This builds off previous flags, and just like the others, may be
    # "false" for situations like the repo staff disabled or is not
    # actually enabled for secret scanning.
    # Returns false if the repo has already been deleted.
    sig { returns(T::Boolean) }
    def results_visible?
      return false if @repo.deleted?
      @token_scanning.enabled?
    end

    # Indicates that the repository:
    # - has Secret Scanning enabled
    # - is a GHAS repo, ie. a repo part of an org that has purchased GitHub Advanced Security
    # Note that  public and archived repos cannot have Advanced Security "enabled",
    # but those repos will still benefit from GHAS scanning if the Org has an active GHAS subscription.
    # Returns false if the repo has already been deleted.
    sig { returns(T::Boolean) }
    def ghas_secret_scanning?
      return false if @repo.deleted?
      return false unless @token_scanning.enabled?
      # make sure this is a GHAS repo
      SecretScanning::Features::AdvancedSecurityHelper.advanced_security_available?(@repo)
    end

    # Whether the repository has validity checks enabled
    # Returns false if the repo has already been deleted.
    sig { returns(T::Boolean) }
    def validity_checks?
      return false if @repo.deleted?
      @validity_checks.enabled?
    end

    # Whether the repository has lower confidence patterns enabled
    sig { returns(T::Boolean) }
    def lower_confidence_patterns?
      return false if @repo.deleted?
      @lower_confidence_patterns.enabled?
    end

    # Whether the repository has generic secrets enabled
    sig { returns(T::Boolean) }
    def generic_secrets?
      return false if @repo.deleted?
      @generic_secrets.enabled?
    end

    # Whether we should scan wikis for this repo
    sig { returns(T::Boolean) }
    def wiki_scanning?
      return false if @repo.deleted?
      @wiki_scanning.enabled?
    end
  end
end
