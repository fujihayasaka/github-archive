# typed: true
# frozen_string_literal: true

module Primer
  module Experimental
    # Public: You may want to use `Comments::PreviewableCommentFormComponent` instead, this one is not actively
    # being maintained.
    # rubocop:disable ViewComponent/ComponentsHaveUnitTests
    class PreviewableMarkdownEditor < Primer::Component # rubocop:disable ViewComponent/EncouragePreviewsForPrimer
      # Anything extra content that needs to be included in the component.
      renders_one :extra

      # @param id [String] The ID of the textarea element.
      # @param name [String] Name attribute of the textarea element.
      # @param system_arguments [Hash] <%= link_to_system_arguments_docs %>
      renders_one :textarea, lambda { |id:, name:, **system_arguments|
        T.bind(self, Primer::Experimental::PreviewableMarkdownEditor)

        @textarea_id = id

        system_arguments[:tag] = :textarea
        system_arguments[:required] = @required
        system_arguments[:autofocus] = @autofocus
        system_arguments[:name] = name
        system_arguments[:classes] = class_names(
          system_arguments[:classes],
          "FormControl-textarea CommentBox-input",
          "js-comment-field",
          "js-quick-submit",
          "js-size-to-fit",
          "js-length-limited-input" => @character_limit.present?
        )

        @help_text_description = "help-text-for-full-description-#{@component_hash}"

        system_arguments[:id] = @textarea_id
        system_arguments[:"aria-describedby"] = @help_text_description
        system_arguments[:"data-input-max-length"] = @character_limit if @character_limit.present?
        system_arguments[:"data-warning-text"] = "{{remaining}} remaining" if @character_limit.present?

        Primer::BaseComponent.new(**system_arguments)
      }

      # @param required [Boolean] Whether or not the input field should be required for form submission.
      # @param preview_path [String] The endpoint that the component should call with the content that is to be rendered.
      # @param system_arguments [Hash] <%= link_to_system_arguments_docs %>
      def initialize(label:, preview_path:, emoji_suggestions_path:, character_limit: nil, required: true, **system_arguments)
        @system_arguments = system_arguments
        @system_arguments[:tag] = :div

        @component_hash = SecureRandom.hex(4)
        @label = label
        @emoji_suggestions_path = emoji_suggestions_path
        @character_limit = character_limit
        @required = required
        @autofocus = system_arguments[:autofocus]

        @system_arguments[:"data-preview-url"] = preview_path
        @system_arguments[:pb] = 2
        @system_arguments[:border] = [nil, nil, true, nil]
        @system_arguments[:border_radius] = 2
        @system_arguments[:classes] = class_names(
          @system_arguments[:classes],
          "CommentBox",
          "js-length-limited-input-container" => @character_limit.present?
        )
      end
    end
    # rubocop:enable ViewComponent/ComponentsHaveUnitTests
  end
end
