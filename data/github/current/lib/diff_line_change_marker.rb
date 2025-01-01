# typed: true
# frozen_string_literal: true

module DiffLineChangeMarker
  include ActionView::Helpers::TagHelper
  include ActionView::Helpers::OutputSafetyHelper
  #
  # Colorization
  #
  # Changed words separated by fewer than MINIMUM_UNCHANGED_LENGTH characters
  # will get combined into a single larger change.
  COLORIZED_LINE_LENGTH_LIMIT = 1024
  # When used with String#split, this will split the string into a sequence of
  # atomic words and individual non-word characters. This means that when a
  # single letter within a word is changed, the whole word will be highlighted.
  # When a single non-word character is changed, only that character will be
  # highlighted.
  DIFF_WORD_BOUNDARY = /(?<=\p{^Word})|(?=\p{^Word})/
  MINIMUM_UNCHANGED_LENGTH = 3

  # Detects changes within a line from a diff and surrounds them with <span
  # class="x"> elements.
  #
  # line - A GitHub::Diff::Line (hopefully with a #related_line).
  #
  # Returns a String containing `line.text`, possibly with <span class="x">
  # elements added to highlight changes.
  def mark_intra_line_changes(line)
    return line.text unless line.related_line
    GitHub.instrument("diff.mark_intra_line_changes") do
      GitHub.dogstats.time("diff", tags: ["action:highlight_words", "type:single_line"]) do
        blocks = compute_intra_line_changes(line.type, line.text, line.related_line.text)
        return line.text if blocks.empty?
        highlighted = blocks.map do |block|
          if block[:changed]
            content_tag(:span, block[:text], { class: "x x-first x-last" })
          else
            block[:text]
          end
        end

        safe_join(highlighted)
      end
    end
  end

  # Detects changes within a syntax-highlighted line from a diff and surrounds
  # them with <span class="x"> elements.
  #
  # line         - A GitHub::Diff::Line.
  # html         - The syntax-highlighted HTML String of this line from the diff.
  # related_html - The syntax-highlighted HTML String of the related line from
  #                the diff. If nil no highlighting will be performed.
  # prefixed     - Whether or not the provided line is prefixed with +/-. Default: true
  #
  # Returns an HTML String containing `html`, possibly with <span class="x">
  # elements added to highlight changes.  The return string is always distinct
  # from the input HTML.
  def mark_intra_line_changes_html(line, html, related_html, prefixed: true)
    return html.dup unless related_html
    return html.dup if line.text.size > COLORIZED_LINE_LENGTH_LIMIT || line.related_line.text.size > COLORIZED_LINE_LENGTH_LIMIT

    return html.dup if GitHub.request_timer.elapsed("diff.mark_intra_line_changes_html") > 1.second && !Rails.env.test?
    GitHub.instrument("diff.mark_intra_line_changes_html") do
      GitHub.dogstats.time("diff", tags: ["action:highlight_words_html", "type:single_line"]) do
        # We wrap the HTML in <div> tags because some versions of libxml won't
        # return top-level text nodes inside a DocumentFragment when we use
        # .xpath(".//text()") below.
        doc = Nokogiri::HTML::DocumentFragment.parse("<div>#{html}</div>")
        related_doc = Nokogiri::HTML::DocumentFragment.parse("<div>#{related_html}</div>")

        blocks = compute_intra_line_changes(line.type, doc.text, related_doc.text, prefixed: prefixed)
        return html.dup if blocks.empty?

        # Convert the blocks into a list of changed ranges.
        change_start = 0
        changed_ranges = T.let([], T::Array[T::Range[Integer]])
        blocks.each do |block|
          change_end = change_start + block[:text].length
          changed_ranges << (change_start...change_end) if block[:changed]
          change_start = change_end
        end

        # Wrap changed text in <span class="x"> elements inside of any existing
        # elements.
        text_start = 0
        doc.xpath(".//text()").each do |node|
          range = changed_ranges.first
          break unless range
          # Loop invariant: text_start < range.last
          # I.e., any changed ranges that end before the current node have already
          # been removed from changed_ranges.

          text = node.text
          text_end = text_start + text.length
          if text_end <= range.first
            # We haven't reached the next changed range yet. Just move along to the
            # next node.
            text_start = text_end
            next
          end

          # The changed range intersects this node.

          if range.first <= text_start && text_end <= range.last && node.parent.name == "span" && node.parent.children.count == 1
            classes = "x".dup
            classes << " x-first" if text_start <= range.first
            classes << " x-last" if range.last <= text_end
            # The entire text node is changed, and we're already within a <span>
            # element. Let's just add "x" to the existing element's class to keep
            # the resulting DOM a bit smaller.
            if !node.parent["class"]
              node.parent["class"] = classes
            elsif node.parent["class"] !~ /\bx\b/
              node.parent["class"] += " #{classes}"
            end
          else
            # The changed range covers some portion of this node. Subsequent ranges
            # may also intersect this node. Let's handle all of them at once.
            consumed = 0
            new_contents = Nokogiri::XML::DocumentFragment.new(doc.document)
            classes = ""
            changed_ranges.each do |range|
              break if text_end <= range.first
              classes = "x".dup
              classes << " x-first" if text_start <= range.first
              classes << " x-last" if range.last <= text_end

              change_start = [text_start, range.first].max - text_start
              change_end = [text_end, range.last].min - text_start
              # Everything before this change is unchanged.
              new_contents << Nokogiri::XML::Text.new(text[consumed...change_start], doc)
              span = Nokogiri::XML::Element.new("span", doc.document)
              span["class"] = classes
              span << Nokogiri::XML::Text.new(text[change_start...change_end], doc)
              new_contents << span
              consumed = change_end
            end
            # Everything after the last change is unchanged.
            new_contents << Nokogiri::XML::Text.new(text[consumed...text.length], doc)
            node.replace(new_contents)
          end

          # Move past any ranges that end within this node.
          while changed_ranges.any?
            range = T.must(changed_ranges.first)
            break if text_end < range.last
            changed_ranges.shift
          end

          # On to the next node!
          text_start = text_end
        end

        # Dig the relevant HTML out of the wrapper container <div> we added at the
        # start.
        result = doc.child.inner_html
        if html.html_safe?
          result.html_safe # rubocop:disable Rails/OutputSafety
        else
          result
        end
      end
    end
  end

  # Private: Compute the changed/unchanged portions of two lines of text from a diff.
  #
  # type     - The type Symbol for this line in the diff, as returned by
  #           GitHub::Diff::Line#type.
  # text     - The unformatted text String of the line from the diff.
  # related  - The unformatted text String of the related line from the diff as
  #           provided by GitHub::Diff::Line#related_line#text. If nil, no
  #           changes will be highlighted.
  # prefixed - Whether or not the provided line is prefixed with +/-. Default: true
  #
  # Returns an Array of Hashes, each with the following keys:
  #   :text    - String containing some substring of `text`.
  #   :changed - Boolean indicating whether this substring is changed or not.
  def compute_intra_line_changes(type, text, related, prefixed: true)
    return [] unless related
    return [] if text.size > COLORIZED_LINE_LENGTH_LIMIT || related.size > COLORIZED_LINE_LENGTH_LIMIT

    old, new = case type
    when :addition
      [related, text]
    when :deletion
      [text, related]
    end

    return [] unless old && new

    old.scrub!
    new.scrub!

    plus_or_minus = (type == :deletion ? old : new)[0..0]

    start = prefixed ? 1 : 0
    old = old[start..-1]
    new = new[start..-1]

    return [] if old.nil? || new.nil?

    old_words = old.split(DIFF_WORD_BOUNDARY)
    new_words = new.split(DIFF_WORD_BOUNDARY)
    words = type == :deletion ? old_words : new_words

    # blocks is an Array describing the changed/unchanged sequences of words.
    # Each item in the Array is a Hash with the following keys:
    #   :changed - Boolean stating whether these words were changed or not.
    #   :range   - The Range of words this block describes. range.exclude_end?
    #              is always true.
    blocks = T.let([], T::Array[T.untyped])

    # Compute changed/unchanged blocks based on the word diff.
    Diff::LCS.diff(old_words, new_words, Diff::LCS::ContextDiffCallbacks).each do |changes|
      previous_change_end = blocks.last ? blocks.last[:range].last : 0
      change_start = type == :deletion ? changes.first.old_position : changes.first.new_position
      # We want change_end to point to just after the last changed word. If the
      # change is for the highlighted string, position will be pointing *at*
      # the last changed word. If the change is for the non-highlighted string,
      # it'll already be pointing just after the last changed word.
      change_is_for_highlighted_string = type == :deletion ? changes.last.deleting? : changes.last.adding?
      change_end = type == :deletion ? changes.last.old_position : changes.last.new_position
      change_end += 1 if change_is_for_highlighted_string

      # Everything between the last change and this one must be unchanged.
      unchanged_range = previous_change_end...change_start

      if blocks.last && words[unchanged_range].sum(&:length) < MINIMUM_UNCHANGED_LENGTH
        # There are so few characters between the last change and this one that
        # it would look noisy to consider them separate changes. Let's just
        # combine them into one big change.
        blocks.last[:range] = blocks.last[:range].first...change_end
        next
      end

      blocks << { changed: false, range: unchanged_range }
      blocks << { changed: true,  range: change_start...change_end }
    end

    # Everything after the last block is unchanged.
    blocks << { changed: false, range: blocks.last[:range].last...words.length } if blocks.last

    return [] unless blocks.any? { |block| block[:changed] }
    blocks.each do |block|
      block_words = words[block[:range]] || []
      block[:text] = block_words.join("")
      block.delete(:range)
    end
    blocks.reject! { |block| block[:text].empty? }

    if prefixed
      [{ changed: false, text: plus_or_minus }] + blocks
    else
      blocks
    end
  end
  private :compute_intra_line_changes
end
