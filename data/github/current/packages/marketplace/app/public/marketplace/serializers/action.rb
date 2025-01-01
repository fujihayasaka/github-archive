# typed: strict
# frozen_string_literal: true

module Marketplace
  module Serializers
    module Action
      extend T::Helpers
      extend Search::RepositoryActionIconHelper

      sig { params(action: RepositoryAction).returns(Marketplace::Types::SerializedActionListing) }
      def self.serialize_model(action)
        {
          categories: categories(action),
          color: action.color,
          description: ::Search.clean_and_sanitize(action.description&.force_encoding(Encoding::UTF_8)),
          iconSvg: svg_icon_string(action.icon_name, owner: action.owner&.display_login),
          id: action.id,
          isVerifiedOwner: action.verified_owner?,
          name: action.name,
          ownerLogin: action.owner&.display_login,
          slug: action.slug,
          stars: action.repository&.stargazer_count || 0,
          type: "repository_action",
          externalUsesPathPrefix: action.external_uses_path_prefix,
          globalRelayId: action.global_relay_id
        }
      end

      sig { params(view: ::Search::RepositoryActionResultView).returns(Marketplace::Types::SerializedActionPreview) }
      def self.serialize_search_view(view)
        action = T.cast(view.repository_action, RepositoryAction)

        {
          color: action.color,
          description: view.description,
          iconSvg: svg_icon_string(action.icon_name, owner: view.owner_display_login),
          id: action.id,
          isVerifiedOwner: view.is_verified_owner,
          name: action.name,
          slug: action.slug,
          type: "repository_action",
        }
      end

      sig { params(action: RepositoryAction).returns(T::Array[T::Hash[Symbol, String]]) }
      def self.categories(action)
        action.categories.map { |category| { name: category.name, slug: category.slug } }
      end
    end
  end
end
