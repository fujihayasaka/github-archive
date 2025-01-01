# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # BlockFenceInputFilter is responsible for detecting all block fences in Markdown and wrapping them in their
  # respective web component elements. Tracking block support is feature flagged on Repositories and only supports
  # issue bodies at this time.
  #
  # BlockFenceInputFilter only supports the tracking block fence at the moment and <tracking-block> web component.
  #
  # Example input:
  #
  #   This is my tracking issue.
  #
  #   ```[tasklist]
  #   - [ ] My draft issue
  #   ```
  #
  # Example output:
  #
  #   This is my tracking issue.
  #
  #   <tracking-block>
  #
  #   ### Tasks
  #
  #   - [ ] My draft issue
  #
  #   </tracking-block>
  #
  # When a persisted tracking block URL is detected, it will be replaced with the list of issues and draft issues
  # contained within as valid Markdown. This enables future HTML pipeline filters to enrich the Markdown, turning it
  # into links, task lists, authorizing access per user, enforcing Conditional Access Policies (CAP), and more.
  class BlockFenceInputFilter < InputFilter
    TRACKING_BLOCK_CODE_FENCE_REGEX = %r{```\[tasklist\][\n|\r]+(?<contents>.*?)([\n|\r|\s]+)?```}m

    # Newline required after opening HTML tag to prevent header from being interpreted as plaintext.
    TRACKING_BLOCK_TEMPLATE = <<~MD

      <tracking-block>

      \\k<contents>

      <tracking-block-omnibar></tracking-block-omnibar>

      </tracking-block>
    MD

    def self.feature_flags
      [:tasklist_block, :tasklist_block_nested_html_pipeline, :tasklist_block_precache]
    end

    def self.cache_key(context)
      return unless context[:tracking_blocks].present?
      context[:tracking_blocks].map(&:url)
    end

    def self.enabled?(context)
      repository = context[:entity]

      return false unless repository.is_a?(Repository)
      return false unless context[:subject].is_a?(Issue) || context[:subject_type] == "Issue"

      # If a repository has the nested HTML pipeline enabled, we no longer need to convert the [tasklist] code fence
      # Markdown to HTML.
      return false if GitHub.flipper[:tasklist_block_precache].enabled?(context[:entity].owner)
      return false if GitHub.flipper[:tasklist_block_nested_html_pipeline].enabled?(repository.owner)
      GitHub.flipper[:tasklist_block].enabled?(repository.owner)
    end

    # Public: Replace each tracking block within provided Markdown with the corresponding URL for each tracking block.
    # Tracking blocks must be populated in the context under `tracking_blocks` key. In the event there are less
    # tracking block objects present in the context than there are tracking blocks in the Markdown, the original
    # Markdown is preserved.
    #
    # TODO: Remove once tasklist_blocks_markdown_at_rest feature fully lands
    #
    # text - The String Markdown to replace tracking blocks in.
    #
    # Examples
    #
    #  replace("```[tasklist]\n- [ ] draft\n```") # => "https://github.com/github/github/issues/123#tracking-block-321"
    #
    # Returns String
    def replace(text)
      return "" if text.nil?

      tracking_blocks = context[:tracking_blocks]
      return text if tracking_blocks.blank?

      # Aggressively add newlines above and below the tracking block, regardless of whether they are present already
      # so that Goomba will always convert the markdown -> html correctly. Otherwise, Markdown will treat two
      # consecutive lines as the same paragraph and render the text as if it was on the same line.
      text.gsub(TRACKING_BLOCK_CODE_FENCE_REGEX).with_index(0) do |match, index|
        if tracking_block = tracking_blocks[index]
          "\n" + tracking_block.url + "\n"
        else
          match
        end
      end
    end

    def call(text)
      return "" if text.nil?
      body = text.dup

      wrap_tracking_block_code_fences(body)

      body
    end

    private

    def wrap_tracking_block_code_fences(body)
      body.gsub!(TRACKING_BLOCK_CODE_FENCE_REGEX, TRACKING_BLOCK_TEMPLATE)
    end
  end
end
