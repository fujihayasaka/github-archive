# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class CodeRenderingServiceFilter < NodeFilter
    def self.feature_flags
      CodeRenderingService.all_markdown_feature_flags
    end

    def self.cache_key(context)
      entity = extract_entity(context)
      supported_views = Viewscreen::MarkdownComponent.supported_views_for_entity(entity)
      if supported_views.empty?
        nil
      else
        "code_rendering_service_markdown:v9:" + supported_views.join(":")
      end
    end

    # Our markdown filter defines a number of different entity types e.g. repository, team, organization
    # that it accepts as entities which are allowed to parse renderable-in-markdown code blocks
    # Most call sites of the pipeline (markdown previews) seem to add the correct entity type to the context in the entity key.
    # This appears to be because the common comment_preview_controller is generally used in context of a repo.
    # HOWEVER, for team posts, there is not a `repository` context available. To handle this case,
    # we need to check the organization to which the user belongs, and supply that as the `entity` our
    # filter checks.
    def self.extract_entity(context)
      context[:entity] || context[:organization] || context[:gist] || context[:check_suite] || context[:page] || context[:memex_project]
    end

    # This selector cannot be memoized.
    # Attempting to call it as a constant within this filter class
    # produces a load error where Rails cannot find classes that live within
    # the zeitwerks-managed `packages` directory.
    def selector
      Goomba::Selector.new(match: CodeRenderingService.selector_list)
    end

    def call(node)
      return node if context[:blob]&.snippet?

      view_data = node.children.first.inner_html
      return node if view_data.blank?

      ui = CodeRenderingService.for_markdown(node["lang"].to_sym, self.class.extract_entity(context), view_data, opts: { html_safe: result[:html_safe] })
      return node if !ui.supports_view?

      ApplicationController.render(ui, formats: [:html], layout: false)
    end
  end
end
