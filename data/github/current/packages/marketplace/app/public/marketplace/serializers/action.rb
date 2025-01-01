# typed: strict
# frozen_string_literal: true

module Marketplace
  module Serializers
    module Action
      extend T::Sig
      extend T::Helpers
      extend Search::RepositoryActionIconHelper

      sig { params(action: RepositoryAction).returns(Marketplace::Types::SerializedActionListing) }
      def self.serialize_model(action)
        {
          categories: action.categories.pluck(:name).map(&:downcase),
          color: action.color,
          description: ::Search.clean_and_sanitize(action.description&.force_encoding(Encoding::UTF_8)),
          iconSvg: svg_icon_string(action.icon_name, owner: action.owner&.display_login),
          id: T.must(action.id),
          isVerifiedOwner: action.verified_owner?,
          name: action.name,
          ownerLogin: action.owner&.display_login,
          slug: action.slug,
          stars: action.repository&.stargazer_count || 0,
          type: "repository_action",
        }
      end

      sig { params(view: ::Search::RepositoryActionResultView).returns(Marketplace::Types::SerializedActionListing) }
      def self.serialize_search_view(view)
        action = T.cast(view.repository_action, RepositoryAction)

        {
          categories: view.categories,
          color: action.color,
          description: view.description,
          iconSvg: svg_icon_string(action.icon_name, owner: view.owner_display_login),
          id: T.must(action.id),
          isVerifiedOwner: view.is_verified_owner,
          name: action.name,
          ownerLogin: action.owner&.display_login,
          slug: action.slug,
          stars: action.repository&.stargazer_count || 0,
          type: "repository_action",
        }
      end
    end
  end
end
