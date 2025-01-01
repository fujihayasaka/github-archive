# typed: true
# frozen_string_literal: true

module Codespaces
  class ValidatePrebuildAccess < Command
    class Error < Codespaces::Error; end

    class AuthorizationError < Error; end
    class CreationCircuitBreaker < Error; end

    attr_reader :repository, :vscs_target, :vscs_target_url, :require_enabled_org

    def initialize(repository:, vscs_target:, vscs_target_url: nil, require_enabled_org: true)
      @repository = repository
      @vscs_target = vscs_target&.to_sym || Codespaces::Vscs.default_target
      @vscs_target_url = vscs_target_url
      @require_enabled_org = require_enabled_org
    end

    def perform
      if repository&.owner&.organization? && require_enabled_org && !::Codespaces::OrgPolicy.enabled_by_organization?(repository.organization)
        raise AuthorizationError, "this organization does not allow codespaces"
      end

      unless repository&.owner.codespaces_feature_enabled?
        raise AuthorizationError, "this repository does not support this feature"
      end

      if vscs_target_url.present? && !GitHub.flipper[:codespaces_developer].enabled?(repository&.owner)
        raise AuthorizationError, "vscs_target_url specified but the repository owner does not have access to developer features"
      end

      if vscs_target != Codespaces::Vscs.default_target && !GitHub.flipper[:codespaces_developer].enabled?(repository&.owner)
        raise AuthorizationError, "vscs_target specified but the repository owner does not have access to developer features"
      end

      if GitHub.flipper[:disable_codespace_creation].enabled?(repository&.owner)
        raise CreationCircuitBreaker, "creation is temporarily unavailable"
      end
    end
  end
end
