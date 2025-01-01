# typed: strict
# frozen_string_literal: true

module Platform
  module Objects
    class IssueFormElementCheckboxOption < Platform::Objects::Base
      description "Checkbox option element inside an issue form checkbox group"

      visibility :under_development

      scopeless_tokens_as_minimum

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

      field :label, String, "The display string of the checkbox option", null: false
      field :label_html, String, "The display string of the checkbox option as html", null: false

      sig { returns(String) }
      def label_html
        checkbox = StructuredTemplates::Checkbox.new(input: object)
        return GitHub::HTMLSafeString::EMPTY if checkbox.label == ""

        markdown = CommonMarker.render_html(checkbox.label, [:UNSAFE, :GITHUB_PRE_LANG], %i[tagfilter table strikethrough autolink])
        GitHub::Goomba::MarkdownPipeline.to_html(markdown).strip.gsub(/^\s?<p?>\s?|\s?<\/p>\s?$/, "")
      end

      field :required, Boolean, "If this option is required to be checked", null: true
    end
  end
end
