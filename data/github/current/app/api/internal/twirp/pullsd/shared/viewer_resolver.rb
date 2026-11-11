# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Pullsd
  module Shared
    # Shared module for resolving a viewer (User) from a Twirp request.
    # Handles hydrating OAuth scopes and bot installations so that
    # downstream visibility checks match the original request's token
    # permissions.
    module ViewerResolver
      extend T::Helpers

      include Api::Internal::Twirp::Pullsd::Shared::InstallationFinder

      # Resolves a viewer from the given request parameters.
      #
      # - Hydrates OAuth scopes from the oauth_access_id so that
      #   Api::AccessControl.scope? checks respect the original token's
      #   granted scopes (a bare User.find_by leaves scopes as nil, which
      #   is treated as "unrestricted").
      # - Sets the bot installation for GitHub App actors.
      #
      # Returns nil if no user is found for the given viewer_id.
      sig do
        params(
          viewer_id: Integer,
          installation_id: Integer,
          installation_type: String,
          oauth_access_id: Integer,
        ).returns(T.nilable(User))
      end
      def resolve_viewer(viewer_id:, installation_id:, installation_type:, oauth_access_id: 0)
        viewer = User.find_by(id: viewer_id)
        return unless viewer

        if oauth_access_id > 0
          access = OauthAccessTokens.domain.by_id(oauth_access_id)
          if access && access.user_id == viewer.id
            viewer.scopes = access.access_level
            viewer.oauth_access = access
          else
            # Fail closed: the token doesn't exist or doesn't belong to the
            # viewer. Return nil so the handler proceeds with no viewer
            # (anonymous visibility), which is more restrictive than leaving
            # scopes as nil (unrestricted).
            return nil
          end
        end

        if viewer.is_a?(Bot) && installation_id > 0
          installation = find_installation_for_bot(viewer, installation_id, installation_type.to_s)
          viewer.installation = installation if installation
        end

        viewer
      end
    end
  end
end
