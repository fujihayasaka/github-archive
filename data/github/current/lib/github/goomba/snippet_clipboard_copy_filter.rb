# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class SnippetClipboardCopyFilter < NodeFilter
    GH_SELECTOR = "gh:snippet-clipboard-copy-content"
    SELECTOR = Goomba::Selector.new("pre")

    def selector
      SELECTOR
    end

    def call(node)
      return unless valid_node?(node)

      options = {}.tap do |opts|
        opts[GH_SELECTOR] = node.text_content

        # Don't strip the "lang" attribute if it's still set.
        # See https://github.com/github/special-projects/issues/313
        if (lang = node["lang"])
          opts["lang"] = lang
        end
      end

      ActionController::Base.helpers.content_tag(:pre, options) do
        safe_html_if_sanitized(node.inner_html)
      end
    end

    def self.enabled?(context)
      show_snippet_buttons?(context) &&
        (repository_context?(context) || organization_context?(context) || check_suite_context?(context) || wiki_context?(context) || context[:force_show_snippet_buttons])
    end

    def self.show_snippet_buttons?(context)
      !context[:hide_snippet_buttons] && !context[:for_email]
    end

    def self.repository_context?(context)
      context.has_key?(:entity) && context[:entity].is_a?(Repository)
    end

    def self.organization_context?(context)
      context.has_key?(:organization) && context[:organization].is_a?(Organization)
    end

    def self.check_suite_context?(context)
      context.has_key?(:check_suite) && context[:check_suite].is_a?(CheckSuite)
    end

    def self.wiki_context?(context)
      return false unless context[:entity].is_a?(::GitHub::Unsullied::Wiki)
      context[:entity].repository.present?
    end

    private

    def valid_node?(node)
      return true if context[:force_show_snippet_buttons]

      # This is to keep compatibility with GitHub::HTML::WikiSnippetClipboardCopyFilter.
      # Once everything is on Goomba this won't be necessary.
      element_nodes = node.children.select { |el| is_element_node?(el) }
      return unless element_nodes.one?

      element_nodes.first.tag == :code
    end
  end
end
