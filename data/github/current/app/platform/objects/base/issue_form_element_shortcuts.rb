# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Base < GraphQL::Schema::Object
      # These methods are common methods to share between the issue form elements
      module IssueFormElementShortcuts
        extend T::Helpers

        requires_ancestor { T.class_of(Platform::Objects::Base) }

        def description_field
          field :description, String, "A description of the input form element which is displayed in the form. Supports Markdown formatting.", null: true
        end

        def description_html_field
          field :description_html, Scalars::HTML, "The description rendered to HTML.", null: true
          include(DescriptionHtmlField)
        end

        module DescriptionHtmlField
          extend T::Helpers

          requires_ancestor { GraphQL::Schema::Object }

          def description_html
            T.bind(self, GraphQL::Schema::Object)
            return nil unless object.description.present?

            markdown = CommonMarker.render_html(object.description, [:UNSAFE, :GITHUB_PRE_LANG], %i[tagfilter table strikethrough autolink])
            GitHub::Goomba::SimplePipeline.to_html(markdown)
          end
        end
      end
    end
  end
end
