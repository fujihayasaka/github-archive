# typed: true
# frozen_string_literal: true

# Called by a `repository.push` subscriber to verify that the codespace's creation metadata is up to date. Specifically
# we are checking if the codespace's OID is no longer valid and fixing it and any possible devcontainer references
# if it is.
module Codespaces
  class VerifyCreationMetadataOnPush < Command
    attr_reader :repository, :branch_name, :user, :force_pushed, :verification_command

    def initialize(repository:, branch_name:, user:, force_pushed:, verification_command: Codespaces::VerifyCreationMetadata)
      @repository, @branch_name, @user, @force_pushed, @verification_command = repository, branch_name, user, force_pushed, verification_command
    end

    def perform
      Codespace.where(repository: repository, ref: branch_name, owner: user).each do |codespace|
        verification_command.call(codespace: codespace, force_pushed:)
      end
    end
  end
end
