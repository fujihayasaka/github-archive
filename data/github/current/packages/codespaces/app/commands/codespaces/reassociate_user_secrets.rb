# typed: true
# frozen_string_literal: true

# Reassociates user secrets when a codespace's underlying repository is changed
# (see packages/codespaces/initializers/codespaces/subscribers.rb) due to a template being published or a fork being
# automatically created for the user on push. The assumption here is that if the user went to the trouble of associating
# user secrets with the codespace's old repository (which was not theirs/writable) then they probably want them to
# be associated with the newly associated repository (which is theirs/writable).
module Codespaces
  class ReassociateUserSecrets < Command
    class Job < CodespacesJob
      def perform(codespace:)
        # Since we're only hitting Credz here we shouldn't need a write connection to the database.
        ReassociateUserSecrets.call(codespace:)
      end
    end

    attr_reader :codespace

    def initialize(codespace:)
      @codespace = codespace
    end

    def perform
      # In order to automatically associate the user's secrets to the codespace's new repository we check that the
      # codespace would be able to receive _all_ secrets which indicates it is pushable now by the codespace owner.
      return unless Codespaces::Policy.can_receive_all_secrets?(codespace)


      previous_repository = if codespace.from_codespace_template?
        codespace.template_repository
      else
        # Only current way to get here is by forking so the previous repository is the parent
        codespace.repository.parent
      end

      return unless previous_repository

      Codespaces::UserSecret.for(codespace.owner).each do |secret|
        secret.fetch_credential
        # We're only trying to update secrets that were already associated with the codespace's pre-publish/fork
        # repository.
        next unless secret.repositories.include?(previous_repository)

        secret.repository_ids << codespace.repository.id
        secret.update
      end
    end
  end
end
