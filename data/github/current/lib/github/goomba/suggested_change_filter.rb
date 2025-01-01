# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class SuggestedChangeFilter < NodeFilter
    SELECTOR_REGEX = 'pre[lang="suggestion" i]'
    SELECTOR = Goomba::Selector.new(SELECTOR_REGEX)
    LINE_PREFIX_REGEX = /\A[ +\-~]/

    def self.cache_key(context)
      [
        ("for_email" if context[:for_email]),
        ("render_suggested_changes_as_text" if context[:render_suggested_changes_as_text]),
        ("include_suggested_changes_id" if context[:include_suggested_changes_id]),
        "line_number=#{(context[:start_line_number] || context[:line_number])}",
        context[:original_lines]&.to_s,
        context[:path],
      ].reject(&:blank?).join(":")
    end

    def selector
      SELECTOR
    end

    # Since this filter turns a code block into a chunk of 'normal' HTML, let's
    # make sure that other filters don't try to reprocess this content
    def halt_further_filters?
      true
    end

    def call(node)
      return node unless original_text
      return node unless new_text = new_text(node)

      if context[:for_email] || context[:render_suggested_changes_as_text]
        render(additions: new_text.split("\n"), deletions: original_text, for_email: true)
      else
        deletions, additions = DiffGenerator.new(original_text.join("\n"), new_text, path).generate_diff
        render(
          additions: additions,
          deletions: deletions,
          line_number: line_number,
          path: path,
          raw_deletions: original_text,
          raw_additions: new_text.split("\n"),
          suggested_change_id: suggested_change_id(new_text),
        )
      end
    end

    private

    def render(locals)
      if context[:diff_component] && context[:diff_component_view_context]
        # Track how many we've rendered
        index = scratch[:suggestion_index] || 0
        scratch[:suggestion_index] = index + 1

        context[:diff_component].new(
          index: index,
          path: path,
          raw_additions: locals[:raw_additions],
          raw_deletions: locals[:raw_deletions],
          start_line_number: line_number,
          hydro_click_tracking_payload: {
            repository_id: comment.repository.id,
            comment_id: comment.id,
            pull_request_id: comment.pull_request.id,
            pull_request_number: comment.pull_request.number,
          },
        ).render_in(context[:diff_component_view_context])
      else
        ApplicationController.render(partial: "filter_partials/suggested_change", locals: locals, formats: [:html])
      end
    end

    def new_text(node)
      node.children&.first&.text_content&.sub(/\n\Z/, "")
    end

    def original_text
      @original_text_content ||= if comment_in_context?
        comment.original_selection.map { |line| line.sub(LINE_PREFIX_REGEX, "") }
      elsif context[:original_lines]
        Array.wrap(context[:original_lines]).map { |line| line.sub(LINE_PREFIX_REGEX, "") }
      end
    end

    def path
      @path ||= if comment_in_context?
        comment.path
      elsif context[:path]
        context[:path]
      end
    end

    def comment_in_context?
      context[:subject].is_a?(PullRequestReviewComment)
    end

    def comment
      context[:subject]
    end

    def line_number
      context[:start_line_number] || context[:line_number]
    end

    def suggested_change_id(new_text)
      return unless context[:include_suggested_changes_id]
      return unless comment_in_context?
      Platform::Models::MobileSuggestedChange.to_global_id(suggestion: new_text, path: path)
    end
  end
end
