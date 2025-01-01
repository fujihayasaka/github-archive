# typed: true
# frozen_string_literal: true

class PullRequest
  # Modify a commit message by unwrapping manually wrapped lines in a
  # way that makes it suitable for use as a suggested PR description.
  #
  # Commit messages are typically wrapped around 72 characters. This makes
  # them somewhat unsuitable as PR descriptions since that wrapping
  # conflicts with the implementation of GitHub Flavored Markdown on
  # github.com. GFM adds a <br> tag after every soft line break, which makes
  # default PR descriptions generated from commits look weird. This class
  # works around that by unwrapping text while preserving other formatting
  # like lists and indented code.
  class CommitMessageUnwrapper
    UL = /[-+*]/
    OL = /[1-9][0-9]*\./
    LIST_MARKER = Regexp.union(UL, OL)
    LIST_ITEM = /(\A\s{0,3}#{LIST_MARKER}\s+).+/
    # This could just go in the general trailer regex but the presence of the
    # email is extra information that yields a better heuristic in some
    # cases.
    EMAIL_TRAILER = /\A(.+)\:\s(.+)>\z/
    QUOTE = /\A\s*>/
    TRAILER = Regexp.union(
      /\A.+:\s+.+\z/,   # GIT_TRAILER_MATCHER, matches e.g. `Something something: blah`
      /\A\s*\[\d+\]\s/, # end note numeric references, e.g. `[1] something`
      /\A\*\s.*:\z/,    # a common idiom in certain OSS codebases like git, e.g. `* tb/commit-graph-genv2-upgrade-fix:`
    )

    def initialize(str)
      @lines = str.split(/\r?\n/)
      @lines_with_indices = @lines.each_with_index.to_a
    end

    def self.call(str)
      new(str).call
    end

    attr_reader :unwrapped_lines, :buf, :handled_current_line

    def call
      precompute_indices
      # set up state flags we will use while processing lines.
      @in_list_item = false
      @in_figure = false
      @last_list_indented_to = -1
      @unwrapped_lines = []
      @buf = []
      @handled_current_line = false
      @in_fence = false
      # Each line in the input will either be emitted verbatim to output or
      # buffered for concatenation with adjacent lines (i.e. unwrapped)
      @lines_with_indices.each do |line, i|
        if line.start_with?("```")
          @in_fence = !@in_fence
        end

        @handled_current_line = false
        if @in_fence
          emit(line)
          next
        elsif line.blank? || QUOTE.match?(line)
          emit(line)
          clear_flags
          next
        elsif figure?(line)
          @in_figure = true
          # disable unwrapping until a blank line is seen
          emit(line)
        elsif email_trailer?(line) || trailer?(i)
          emit(line)
        elsif matches_list_item?(line)
          @in_list_item = true # remember that we are currently processing
          flush                # a list since it changes handling.
          buffer(line)
          next
        elsif line.start_with?(" ", "\t") # anything indented gets left alone
          if T.unsafe(@in_list_item)      # unless it's a continued list item
            buffer(line.lstrip)
            next
          elsif continues_previous_list_item?(line)
            @in_list_item = true
            buffer(line)
            next
          else
            emit(line)
          end
        end

        @in_list_item = false
        next if handled_current_line

        if line.length < 50 # short lines shouldn't be unwrapped unless they
          if buf.any?       # are the last line of an existing paragraph
            buf << line
            flush
          else # standalone short line, leave alone
            emit(line)
          end
        else
          @last_list_indented_to = -1
          buf << line
        end
      end
      flush
      unwrapped_lines.join("\n")
    end

    private

    def precompute_indices
      precompute_blank_indices
      precompute_group_indices
      precompute_trailer_indices
    end

    # Chunk the line indices into groups separated by blank lines.
    def precompute_group_indices
      @index_groups = @lines_with_indices.map(&:last).chunk_while do |_before, after|
        !@blank_indices.include?(after)
      end.map do |group|
        group.reject { |index|  @blank_indices.include?(index) }
      end
    end

    # Our trailer regular expression by itself is subject to false positives.
    # Tighten the heuristic by only considering a line to be a trailer if it
    # matches the regular expression and is within a group of lines which _all_
    # match the regular expression.
    def precompute_trailer_indices
      trailer_match_indices = @lines_with_indices.select { |l, _| TRAILER.match?(l) }.map(&:last)
      matching_groups = @index_groups.select do |group|
        group.all? { |index| trailer_match_indices.include?(index) }
      end
      @trailer_indices = Set.new(matching_groups.flatten)
    end

    def precompute_blank_indices
      @blank_indices = Set.new(@lines_with_indices.select { |l, _| l.blank? }.map(&:last))
    end

    def clear_flags
      @in_figure = false
      @in_list_item = false
    end

    def indent_cols(line)
      line.index(/[^\s]/)
    end

    def last_nonblank_emitted_line
      unwrapped_lines.reverse_each.detect { |line| !line.blank? }
    end

    # After multiple levels of indent nesting we start to misidentify list item
    # markers because we limit the number of leading space in our list item
    # marker matching regex so as not to interfere with code listings that have
    # leading `-` chars.
    #
    # This function allows us to recognize list item markers at any nesting
    # depth by running the regex _relative to the last encountered indent
    # level_. This makes things a bit more complex but IMO it's worth
    # it. It's a bit tricky though, we only want to apply this for
    # situations where we've indented since the last emitted line, or
    # else we might trim nonblank content off our line.
    def trim_left_margin_relative_to_last_line(line)
      this_indent = indent_cols(line)
      last_line = last_nonblank_emitted_line
      last_indent = last_line ? indent_cols(last_line) : 0
      # do not trim if we've dedented or are flat since the last emitted line
      if this_indent > last_indent
        trim_pos = last_indent
        line[trim_pos...]
      else
        line
      end
    end

    def matches_list_item?(line)
      text = trim_left_margin_relative_to_last_line(line)
      match = LIST_ITEM.match(text) or return false
      # Store this offset we can detect subsequent paragraphs that are part of
      # the same list item (because they indent to the same offset)
      @last_list_indented_to = match.end(1) # string offset of first char post-match
    end

    # We can detect by looking at the indent that this is a subsequent
    # paragraph of a previous list item, e.g. the second item below:
    #
    #    * first list item
    #
    #    * second list item
    #
    #      this is still the second list item
    #      and this line should be unwrapped
    #
    #    * third list item
    #
    def continues_previous_list_item?(line)
      line.index(/[^\s]/) == @last_list_indented_to
    end

    def figure?(line)
      # Multiple adjacent interior spaces is a good indicator some ASCII-art is afoot.
      @in_figure || line.strip.include?("   ")
    end

    def email_trailer?(line)
      EMAIL_TRAILER.match?(line)
    end

    def trailer?(index)
      @trailer_indices.include?(index)
    end

    # Append some text to the final output array.
    def emit(line)
      flush
      unwrapped_lines << line
      @handled_current_line = true
    end

    # We decided that the line we're looking at is joinable with preceeding ones.
    def buffer(line)
      buf << line
      @handled_current_line = true
    end

    def flush
      if buf.any?
        unwrapped_lines << buf.join(" ")
        buf.clear
      end
    end
  end
end
