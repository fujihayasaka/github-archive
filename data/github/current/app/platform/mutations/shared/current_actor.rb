# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    module Shared
      module CurrentActor
        extend T::Helpers

        requires_ancestor { Platform::Mutations::Base }

        # Determine the actor to perform authorization against.
        # See https://thehub.github.com/epd/engineering/dev-practicals/secure-coding/secure-coding-general/auth-on-api/
        def current_actor(repository)
          if context[:permission].installation.present?
            # GitHub App Installation ("Server-to-server") - use the corresponding Bot
            context[:permission].installation.bot
          elsif context[:permission].integration.present?
            # Github App ("Integration") - use the same logic as Platform::Authorization::UserToServerAuthorizer#granular_actor_on_repository
            context[:permission].integration.installations.not_suspended.with_repository(repository).first&.bot
          elsif context[:permission].viewer.programmatic_access.present?
            # Fine-Grained PATs - use the ProgrammaticAccessBot associated with the ProgrammaticAccessGrant
            grant = context[:permission].viewer.programmatic_access.grant
            grant.bot || Platform::Loaders::BotByUserProgrammaticAccessGrant.load(grant).sync
          else
            # User - just use the viewer
            context[:permission].viewer
          end
        end
      end
    end
  end
end
