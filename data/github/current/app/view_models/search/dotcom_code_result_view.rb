# typed: true
# frozen_string_literal: true

module Search
  # A "presenter" class that wraps up a source code search result from the dotcom api. It provides
  # some nice methods for iterating highlighted search fragments and rendering
  # them in a rails view.
  #
  class DotcomCodeResultView < CodeResultView
    attr_reader :file_url, :private, :blob_sha, :last_modified_at, :repo_nwo, :language,
                :repo_owner, :owner_display_login, :number_of_matches, :repo_link, :line_numbers

    alias :private? :private

    # Create a new code result from the Hash returned from the dotcom api.
    #
    # hash - Source code result Hash from the dotcom api search.
    #
    def initialize(dotcom_hash)
      @path       = dotcom_hash["path"]
      @filename   = dotcom_hash["name"]
      @blob_sha   = dotcom_hash["sha"]
      @file_url   = dotcom_hash["html_url"]
      @language   = dotcom_hash["language"]
      @file_size  = dotcom_hash["file_size"]
      @last_modified_at = Time.parse(dotcom_hash["last_modified_at"])
      @line_numbers = line_numbers_range(dotcom_hash["line_numbers"])

      repo            = dotcom_hash["repository"]
      @repo_id        = repo["id"]
      @repo_link      = repo["html_url"]
      @repo_nwo       = repo["full_name"]
      @private        = repo["private"]
      @repo_owner     = repo["owner"]
      @owner_display_login    = repo_owner["login"]

      highlighted_text   = text_matches(dotcom_hash["text_matches"])
      @highlights        = highlighted_text.first
      @number_of_matches = highlighted_text.last

      @file = cleanup_line_endings(@highlights["file"]&.join || "")
    end

    # getting highlights from the text matches
    def text_matches(text_matches)
      return nil if text_matches.empty?

      highlights = Hash.new
      number_of_matches = 0
      text_matches.each_with_index do |text_match, idx|
        key = text_match["property"]
        fragment = text_match["fragment"].dup
        number_of_matches += text_match["matches"].size
        inserted = 0
        text_match["matches"].each do |matches|
          fragment.insert(matches["indices"].first + inserted, ESCAPED_PRE_TAG)
          inserted += ESCAPED_PRE_TAG.length
          fragment.insert(matches["indices"].last + inserted, ESCAPED_POST_TAG)
          inserted += ESCAPED_POST_TAG.length
        end
        # Later methods (e.g. `file`) rely on `fragment` being modified
        text_match["fragment"] = fragment

        if key == "content"
          key = "#{key}-#{idx}"
        end
        highlights[key] = [fragment]
      end
      file_highlights = highlights.keys.select { |key| key.match(/content/) }
      if file_highlights
        highlights["file"] = []
        file_highlights.each { |key| highlights["file"] << highlights[key].join }
      end
      [highlights.compact, number_of_matches]
    end

    # Public: Return a collection of CodeHighlighter instances that can be
    # iterated and enumerated.
    #
    # Returns an Array of CodeHighlighter instances.
    #
    def highlights
      if has_file_highlights?
        highlighted_fragments = collect_highlighted_fragments(@highlights["file"])

        if highlighted_fragments.length == 2
          if fragments_repeat?(@line_numbers.first, @line_numbers.last) || \
              fragments_swapped?(@line_numbers.first, @line_numbers.last)
            highlighted_fragments.reverse!
            @line_numbers.reverse!
          end
          # combine two separate fragments into one, to avoid duplicating lines. see http://git.io/uaEP4w
          if fragments_match?(@line_numbers.first, @line_numbers.last)
            highlighted_fragments.pop
          elsif fragments_overlap?(@line_numbers.first, @line_numbers.last)
            highlighted_fragments = merge_two_fragments(highlighted_fragments.first, highlighted_fragments.last)
          end
        end

        highlighted_fragments
      else
        [CodeHighlighter.new(file, hl_code: hl_file, language: language)]
      end
    end

    # Internal: Iterates over the 'file' highlights and returns a new CodeHighlighter
    # instance for each one.
    #
    # This will be at most two instances, since we only ask for two fragments.
    #
    # Retuns an array of CodeHighlighter objects.
    def collect_highlighted_fragments(file_highlights)
      file_highlights.enum_for(:each_with_index).collect do |fragment, index|
        fragment = cleanup_line_endings(fragment)
        CodeHighlighter.new(
          file, hl_code: hl_file,
          language: language,
          fragment: fragment,
          line_numbers: @line_numbers[index]
        )
      end
    end

    # Public: Combines two fragments into one, to avoid duplicating lines.
    # See http://git.io/uaEP4w for more information.
    #
    # first_fragment - The first set of CodeHighlighter results
    # second_fragment - The second set of CodeHighlighter results
    #
    # Returns a single CodeHighlighter combining the two fragments.
    def merge_two_fragments(first_fragment, second_fragment)
      lines_to_skip = 1

      appendable_lines = second_fragment.lines.from(lines_to_skip)
      appendable_fragment = second_fragment.fragment.split("\n").from(lines_to_skip).join("\n")
      appendable_dotcom_fragment = second_fragment.dotcom_fragment.split("\n").from(lines_to_skip).join("\n")

      first_fragment.lines.push(*appendable_lines)
      first_fragment.fragment += "\n#{appendable_fragment}"
      first_fragment.dotcom_fragment += "\n#{appendable_dotcom_fragment}"
      first_fragment.line_numbers = first_fragment.line_numbers.first..second_fragment.line_numbers.last
      first_fragment.dotcom_search_line_numbers = @line_numbers.first.first..@line_numbers.last.last

      [first_fragment]
    end

    # Public: Accessor for the highlighted file path. If there is no
    # highlighting on the file path, then the normal path is returned but HTML
    # escaped.
    #
    # Returns the highlighted file path as a String.
    #
    def hl_path
      path = if has_path_highlights?
        # replace the filename with the highlighted path
        [@path.split("/")[0...-1], @highlights["path"].first].join("/")
      else
        @path
      end
      escape_and_replace_highlight_tags(path.dup)
    end

    # Public: Accessor for the highlighted file name. If there is no
    # highlighting on the file name, then the normal name is returned but HTML
    # escaped.
    #
    # Returns the highlighted file name as a String.
    #
    def hl_filename
      filename = if has_path_highlights?
        @highlights["path"].first
      else
        @filename
      end
      escape_and_replace_highlight_tags(filename.dup)
    end

    # Takes the line_numbers array of strings and returns array of ranges
    #
    # Returns array of ranges
    def line_numbers_range(line_numbers_array)
      line_numbers_array.map do |line_numbers|
        Range.new(*line_numbers.split("..").map(&:to_i))
      end
    end
  end  # CodeResultView
end  # Search
