# typed: true
# frozen_string_literal: true

module Codespaces
  # Finds or creates a user-owned fork of the codespace's repository.
  # The codespace is "reassigned" to that repository along with its tokens.
  #
  # Returns a branch name where clients can safely push changes, prioritizing
  # a specified :preferred_branch param. If the fork already existed and the parent repo
  # has since seen new changes on that preferred branch, a new branch name will be generated.
  #
  # The client invoking this command is responsible for updating git configuration
  # within the codespace to point to the new remote.
  class ForkRepo < Command
    class UnforkableRepository < StandardError; end
    class UserOwnsParentRepository < StandardError; end
    class InstallationUpdateFailed < StandardError; end

    attr_reader :codespace, :preferred_branch, :entry_point

    # preferred_branch: prioritize return this as a safe branch to push changes to, unless it has upstream changes on the parent.
    def initialize(codespace, preferred_branch, entry_point:)
      @codespace = codespace
      @preferred_branch = preferred_branch
      @entry_point = entry_point
    end

    def perform
      original_repository = codespace.repository
      # Note: if the forker (the codespace owner here) owns the parent repository of the repository that #fork is called on,
      # the parent will be returned from "#fork"
      forked, reason, errors = original_repository.fork(forker: codespace.owner)
      raise UnforkableRepository, Repository::ForkerMethods.message_from_reason(reason, errors) unless forked && forked.pushable_by?(codespace.owner)
      unless GitHub.flipper[:codespaces_test_secret_escalation].enabled?(codespace.owner)
        raise UserOwnsParentRepository, "Your account already owns an ancestor of this repository" if reason == :exists && original_repository.parents.include?(forked)
      end
      safe_branch = preferred_branch.presence || random_branch
      while branch_has_upstream_changes?(forked, safe_branch)
        safe_branch = random_branch
      end

      Codespaces::SwitchRepository.call(codespace, forked)

      update_installations(forked, original_repository.owner)

      [forked, safe_branch]
    end

    private

    def branch_has_upstream_changes?(forked, branch)
      return false if forked.empty?
      return false unless forked.heads.include?(branch)

      oid = Codespaces::GetTargetRef.call(repository: codespace.repository, name_or_oid: branch)&.target_oid
      forked_oid = Codespaces::GetTargetRef.call(repository: forked, name_or_oid: branch)&.target_oid

      oid != forked_oid
    end

    def random_branch
      "codespace-#{SecureRandom.hex(2)}"
    end

    def update_installations(forked, original_repository_owner)
      # find active installations associated with the user and the codespaces integration
      valid_codespace_owner_oauth_access_ids = OauthAccess
        .where(user: codespace.owner, installation_type: "SiteScopedIntegrationInstallation")
        .where("expires_at_timestamp > ?", Time.now.to_i)
        .distinct
        .pluck(:installation_id)

      integration = ::Apps::Privileged.integration(:codespaces_production)

      installations = SiteScopedIntegrationInstallation.where(
          id: valid_codespace_owner_oauth_access_ids,
          integration: integration,
          target: original_repository_owner,
        ).where(
          "expires_at > ?", Time.now.to_i
        ).select do |installation|
          codespace.id.in?(installation.codespace_ids)
        end

      update_installation_args = {
        repositories: [forked],
        repository_permissions: Repository::Resources.filter(integration.default_permissions),
        entry_point: entry_point,
      }

      # Give existing installations access to this fork
      results = installations.map do |associated_installation|
        result = SiteScopedIntegrationInstallation::Editors::Repository.grant(associated_installation, **update_installation_args)
        raise InstallationUpdateFailed, result.reason if result.failed?
      end
    end
  end
end
