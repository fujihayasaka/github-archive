# typed: true
# frozen_string_literal: true

module Codespaces
  class CreateEnvironment < Command
    class TimeoutError < Codespaces::Client::TimeoutError; end

    attr_reader :codespace, :environment_options, :request_cascade_token

    def initialize(codespace, github_token:, request_cascade_token: false, environment_options: {})
      @codespace = codespace
      @environment_options = environment_options
      @request_cascade_token = request_cascade_token
      @github_token = github_token
    end

    def perform
      devcontainer_path = codespace.devcontainer_path.presence
      devcontainer_tree_entry = Codespaces::DevContainer.new(repository: codespace.repository, oid: codespace.oid, filepath: devcontainer_path).tree_entry

      # if no devcontainer path was passed but we find one in a default location, set it so we know which was used
      if devcontainer_path.blank? && devcontainer_tree_entry
        codespace.devcontainer_path = devcontainer_tree_entry&.path
        codespace.save!
      end

      environment_options[:devcontainerPath] = codespace.devcontainer_path
      environment_options[:devcontainerJson] = devcontainer_tree_entry&.data
      environment_options[:hasDevcontainerJson] = !!devcontainer_tree_entry

      # Should we remove the .git installation in the codespace's repository, to decouple it from the
      # "template" and force the user to publish to a new repo?
      if codespace.from_codespace_template?
        environment_options[:features] ||= {}
        environment_options[:features][:removeRepoGit] = true
        # It's possible for the codespace to have been created from a template repository but that repo's owner may
        # have disabled template option on the repo by the time we get here meaning we won't find a template anymore.
        # It's clearly not the blank template though if that's the case so lets just set things up to reinit the git
        # repo and move on with our lives as if this timing problem didn't happen.
        if codespace.requires_git_reinit?
          environment_options[:features][:reinitRepoGit] = true
        end
      end

      client.create_environment(
        codespace.location,
        codespace.repository,
        environment_options: environment_options,
        sku_name:            codespace.sku_name,
        name:                codespace.name,
        moniker:             codespace.moniker,
        github_token:        @github_token,
        codespace_token:     Codespaces::Tokens.mint_codespace_token(scope: Codespaces::Tokens::GPG_AUTHORIZATION_SCOPE, user: codespace.owner, codespace: codespace),
        secrets: secrets,
        request_cascade_token: request_cascade_token,
        billable_owner: codespace.billable_owner,
        prebuild_allowed: Codespaces::Secret.prebuild_allowed?(codespace: codespace),
        create_type: codespace.create_type,
      )
    rescue Codespaces::Client::TimeoutError => e
      raise TimeoutError.new(e)
    end

    private

    def client
      @client ||= Codespaces::VscsClient.for_codespace(codespace)
    end

    def secrets
      secrets = []
      max_attempts = 3
      attempts = 0
      retry_backoff = 0.2

      begin
        attempts += 1
        secrets = Codespaces::Secret.assemble(codespace, host_setup: true)
      rescue Secrets::Error => e
        Codespaces::ErrorReporter.report(e)
        if attempts <= max_attempts
          sleep retry_backoff
          retry
        else
          GitHub.dogstats.increment("codespaces.create.secrets", tags: ["outcome:failure", "attempts:#{attempts}"])
          raise
        end
      end
      GitHub.dogstats.increment("codespaces.create.secrets", tags: ["outcome:success", "attempts:#{attempts}"])

      secrets
    end
  end
end
