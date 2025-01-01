# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  class HasUnpushedChanges < Command
    def initialize(
      codespace:,
      user: codespace.owner,
      client: Codespaces::VscsClient
    )
      @codespace = codespace
      @user = user
      @client = client
    end

    def perform
      return false unless @codespace.provisioned?

      env = @client.for_codespace(@codespace, user: @user).fetch_environment(@codespace.guid)
      env ? env["hasUnpushedGitChanges"] : false
    end
  end
end
