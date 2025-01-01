# typed: strict
# frozen_string_literal: true

module Platform
  module Objects
    class IssueFormElementMarkdown < Platform::Objects::Base
      visibility :under_development

      description "Markdown element in an issue form"

      model_name "Markdown"

      implements Interfaces::IssueFormElement

      sig { params(permission: T.untyped, _object: T.untyped).returns(T::Boolean) }
      def self.async_api_can_access?(permission, _object)
        # This is only called internally as a field in the IssueForm object
        # and visibility is pre-checked on the Repository object.
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      sig { params(permission: T.untyped, object: T.untyped).returns(T::Boolean) }
      def self.async_viewer_can_see?(permission, object)
        # This is only called internally as a field in the IssueForm object
        # and visibility is pre-checked on the Repository object.
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # Renaming value because here it's required, but in the other elements (that make up the union) it is optional
      field :content, String, "The text that is rendered. Markdown formatting is supported.", null: false
      sig { returns(String) }
      def content
        object.value
      end

      field :content_html, String, "The HTML rendered from the content field.", null: false
      sig { returns(String) }
      def content_html
        return GitHub::HTMLSafeString::EMPTY if content == ""

        GitHub::Goomba::MarkdownPipeline.to_html(content)
      end
    end
  end
end
