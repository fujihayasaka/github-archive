# typed: true
# frozen_string_literal: true

module Dependabot
  class AutomaticInstallationCheck
    attr_reader :repository

    def initialize(repository)
      @repository = repository
    end

    def should_install?
      return false if security_updates_disabled?
      return false if not_required?

      repository_is_eligible?
    end

    private

    # Repositories are created with an explicit enabled/disabled flag
    # based on the owner's configuration at time of creation.
    #
    # Unless a Repository is _explicitly_ enabled we should not
    # automatically install.
    #
    # See: app/models/repository/security_products_dependency.rb
    def security_updates_disabled?
      !repository.vulnerability_updates_enabled?
    end

    def not_required?
      repository.fork? || repository.dependabot_installed?
    end

    def repository_is_eligible?
      return false if repository.locked? || repository.deleted?

      repository.active? && repository.maintained?
    end
  end
end
