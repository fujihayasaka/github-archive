# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class CodeRenderingServiceFilter < NodeFilter
    # When enabled, the component is handed the code block's decoded text and
    # escapes it on render. When disabled, we fall back to the legacy behavior
    # of handing over the block's already-sanitized, serialized HTML with its
    # quote delimiters rewritten to `&quot;` and the result trusted verbatim.
    # Remove this flag (and the legacy branch) once fully rolled out.
    SKIP_QUOTE_REWRITE_FLAG = :code_rendering_service_skip_quote_rewrite
    SKIP_QUOTE_REWRITE_CACHE_KEY = "skip_quote_rewrite"

    def self.feature_flags
      CodeRenderingService.all_markdown_feature_flags + [SKIP_QUOTE_REWRITE_FLAG]
    end

    # Actor-gated on the entity whose markdown is being rendered when that
    # entity is a valid vexi actor (Repository, Organization, ...); everything
    # else (check suites, wiki pages, memex projects) falls through to a global
    # check so the rollout can finish in one step.
    def self.skip_quote_rewrite?(context)
      actor = extract_entity(context)
      if actor.respond_to?(:vexi_id)
        FeatureFlag.vexi.enabled?(SKIP_QUOTE_REWRITE_FLAG, actor, default: false)
      else
        FeatureFlag.vexi.enabled?(SKIP_QUOTE_REWRITE_FLAG, default: false)
      end
    end

    def self.cache_key(context)
      entity = extract_entity(context)
      supported_views = Viewscreen::MarkdownComponent.supported_views_for_entity(entity)
      if supported_views.empty?
        nil
      else
        key = "code_rendering_service_markdown:v9:" + supported_views.join(":")
        # Folding the flag in splits the shared render cache into enabled and
        # disabled cohorts during rollout. Goes away with the flag.
        if skip_quote_rewrite?(context)
          return "#{key}:#{SKIP_QUOTE_REWRITE_CACHE_KEY}"
        end
        key
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

      if self.class.skip_quote_rewrite?(context)
        # Use the decoded text content rather than the serialized HTML of the
        # code block: the component escapes what it renders, so handing it
        # markup would let attributes the pipeline's sanitizer rejected survive.
        view_data = node.text_content
        opts = { skip_quote_rewrite: true }
      else
        view_data = node.children.first.inner_html
        opts = { html_safe: result[:html_safe] }
      end
      return node if view_data.blank?

      ui = CodeRenderingService.for_markdown(node["lang"].to_sym, self.class.extract_entity(context), view_data, opts: opts)
      return node if !ui.supports_view?

      ApplicationController.render(ui, formats: [:html], layout: false)
    end
  end
end
