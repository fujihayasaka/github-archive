# typed: true
# frozen_string_literal: true

module Search
  # A "presenter" class that wraps up a source code search result. It provides
  # some nice methods for iterating highlighted search fragments and rendering
  # them in a rails view.
  #
  class CodeResultView

    # Files larger than 100K should not be run through pygments. Only
    # highlight the sections that have search syntax matches.
    MAX_PL_FILE_SIZE = 100 * 1024

    # File fragments large than 10K should not be run through pygments. If
    # this is the case, then one of the matching lines is waaaay too long.
    MAX_PL_FRAGMENT_SIZE = 10 * 1024

    # These escaped tags are used to find the highlighted sections
    ESCAPED_PRE_TAG  = Regexp.escape(::Search::Queries::CodeQuery::PRE_TAG)
    ESCAPED_POST_TAG = Regexp.escape(::Search::Queries::CodeQuery::POST_TAG)

    attr_reader :id, :path, :filename, :file, :file_size, :repo_id, :public, :language, :blob_sha, :commit_sha, :timestamp
    attr_reader :repo, :repo_name, :repo_owner, :owner_login, :explain, :match_count, :language_color, :repo_default_branch, :hl_fragments
    attr_accessor :hl_file

    alias :public? :public

    # Public: Create CodeResultView instances all of the given search result
    # hashes. This batched interface allows syntax highlighting to be performed
    # in parallel.
    #
    # hashes - An Array of code search result Hashes from the search index.
    #
    # Returns the given array, with the hashes replaced with `CodeResultView`
    # instances.
    def self.build_batch(hashes)
      scopes = []
      file_contents = []
      highlighted_views = []

      # Create a view for each result hash. This reuses the input array.
      all_views = hashes.map! do |hash|
        view = new(hash)

        # Collect up the scope names and contents for all of the results
        # whose file is small enough to syntax-highlight in its entirety.
        # This way, these files can be highlighted in parallel via a single
        # `highlight_many` call.
        if view.file_size <= MAX_PL_FILE_SIZE
          if scope = Linguist::Language[view.language].try(:tm_scope)
            file_contents.push(view.file)
            scopes.push(scope)
            highlighted_views.push(view)
          else
            lines = GitHub::Colorize.highlight_plain(view.file)
            view.hl_file = CodeHighlighter.process_lines(lines)
          end
        end

        view
      end

      # Syntax-highlight the files in parallel. For all the files that
      # highlight successfully, assign the highlighted content on the
      # corresponding CodeResultView.
      GitHub::Colorize
        .highlight_many(scopes, file_contents)
        .each_with_index do |document, i|
          if document
            highlighted_views[i].hl_file = CodeHighlighter.process_lines(document)
          end
        end

      all_views
    end

    # Public: Create a CodeResultView from the given search result hash.
    # This is mainly for testing. In production, use .build_batch instead.
    def self.build(hash)
      self.build_batch([hash]).first
    end

    # CodeResultView instances should not be created directly, because
    # their construction relies on logic in .build_batch, which operates
    # on multiple results at a time.
    private_class_method :new

    HIGHLIGHT_CSS_CLASSES = "text-bold hx_keyword-hl rounded-2 d-inline-block"

    # Create a new code result from the Hash returned from the search index.
    #
    # hash - Source code result Hash from the search index.
    #
    def initialize(hash)
      source = hash["_source"]

      @id         = hash["_id"]
      @path       = source["path"]
      @filename   = source["filename"]
      @file       = source["file"].to_s.scrub
      @file_size  = source["file_size"]
      @repo_id    = source["repo_id"]
      @public     = source["public"]
      @language   = Search.language_name_from_id(source["language_id"])
      @blob_sha   = source["blob_sha"]
      @commit_sha = source["commit_sha"]
      @timestamp  = Time.parse(source["timestamp"])
      @explain    = hash["_explain"]

      @file = cleanup_line_endings(@file)

      @repo = hash["_model"]
      @repo_name   = @repo.name_with_display_owner
      @repo_owner  = @repo.owner
      @owner_login = @repo.owner.display_login

      @highlights = hash["highlight"]

      if @highlights && (@highlights["path"] || @highlights["filename"])
        hl = []
        hl << (@highlights["path"] ? @highlights["path"].first : @path)
        hl << (@highlights["filename"] ? @highlights["filename"].first : @filename)
        hl = hl.compact.join("/")
        @highlights["path"] = [hl]
      end

      sanity_check_file_highlights!

      @path = @path.nil? ? @filename : "#{@path}/#{@filename}"
    end

    def has_file_highlights?
      @highlights and @highlights["file"]
    end

    def has_path_highlights?
      @highlights and @highlights["path"]
    end

    def has_filename_highlights?
      @highlights and @highlights["filename"]
    end

    # Public: Iterate over each search highlighted code fragment and yield a
    # CodeHighlighter instance for that fragment. The CodeHighlight is used to
    # render the search highlighted syntax highlighted source code fragment
    # lines ... o_O
    #
    # Yields a CodeHighlighter instance.
    #
    # Returns this CodeResult instance.
    #
    def each_highlight(&block)
      highlights.each(&block)
    end

    # Public: Iterate over each search highlighted code, and count how many highlighted
    # terms there are
    #
    # Returns a Number.
    #
    def number_of_matches
      matches = 0
      each_highlight do |highlight|
        matches += highlight.fragment.scan(/#{ESCAPED_PRE_TAG}/).length if highlight.fragment?
      end
      matches
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
          if fragments_repeat?(highlighted_fragments.first.line_numbers, highlighted_fragments.last.line_numbers) || \
              fragments_swapped?(highlighted_fragments.first.line_numbers, highlighted_fragments.last.line_numbers)
            highlighted_fragments.reverse!
          end
          # combine two separate fragments into one, to avoid duplicating lines. see http://git.io/uaEP4w
          if fragments_match?(highlighted_fragments.first.line_numbers, highlighted_fragments.last.line_numbers)
            highlighted_fragments.pop
          elsif fragments_overlap?(highlighted_fragments.first.line_numbers, highlighted_fragments.last.line_numbers)
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
      file_highlights.collect do |fragment|
        fragment = cleanup_line_endings(fragment)
        CodeHighlighter.new(file, hl_code: hl_file, language: language, fragment: fragment)
      end
    end

    # Internal: Determines if the first fragment range actually appears after
    # the second fragment range.
    #
    # first_fragment_line_numbers - The range of the first set of CodeHighlighter results
    # second_fragment_line_numbers - The range of the second set of CodeHighlighter results
    #
    # Returns a True/False value.
    def fragments_swapped?(first_fragment_line_numbers, second_fragment_line_numbers)
      first_fragment_line_numbers.first > second_fragment_line_numbers.first
    end

    # Internal: Determines if the second fragment range is just the same as the
    # first line in the first fragment fragment.
    #
    # first_fragment_line_numbers - The range of the first set of CodeHighlighter results
    # second_fragment_line_numbers - The range of the second set of CodeHighlighter results
    #
    # Returns a True/False value.
    def fragments_repeat?(first_fragment_line_numbers, second_fragment_line_numbers)
      second_fragment_line_numbers.size == 1 && \
      first_fragment_line_numbers.first == second_fragment_line_numbers.first
    end

    # Internal: Determines if the range of the first fragment clashes with the range
    # of the second.
    #
    # first_fragment_line_numbers - The range of the first set of CodeHighlighter results
    # second_fragment_line_numbers - The range of the second set of CodeHighlighter results
    #
    # Returns a True/False value.
    def fragments_overlap?(first_fragment_line_numbers, second_fragment_line_numbers)
      first_fragment_line_numbers.last >= second_fragment_line_numbers.first
    end

    # Internal: Determines if the range of the first fragment is the same as the range
    # of the second.
    #
    # first_fragment_line_numbers - The range of the first set of CodeHighlighter results
    # second_fragment_line_numbers - The range of the second set of CodeHighlighter results
    #
    # Returns a True/False value.
    def fragments_match?(first_fragment_line_numbers, second_fragment_line_numbers)
      first_fragment_line_numbers == second_fragment_line_numbers
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

      # fetch relevant properties from the second fragment
      if second_fragment.hl_lines?
        appendable_hl_lines = second_fragment.hl_lines.from(lines_to_skip)
      end
      appendable_lines = second_fragment.lines.from(lines_to_skip)
      appendable_fragment = second_fragment.fragment.split("\n").from(lines_to_skip).join("\n")

      # merge the second fragment's properties  into the first fragment
      if first_fragment.hl_lines? && second_fragment.hl_lines?
        first_fragment.hl_lines.push(*appendable_hl_lines)
      end
      first_fragment.lines.push(*appendable_lines)
      first_fragment.fragment += "\n#{appendable_fragment}"
      first_fragment.line_numbers = first_fragment.line_numbers.first..second_fragment.line_numbers.last

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
        @highlights["path"].first
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
      filename = if has_filename_highlights?
        @highlights["filename"].first
      else
        @filename
      end
      escape_and_replace_highlight_tags(filename.dup)
    end

    # Internal: HTML escapes the input HTML and replaces the custom PRE_TAG and
    # POST_TAG values with <span> and </span> tags respectively. The returned string
    # is `html_safe` and can be used in a template.
    #
    # Returns the highlighted HTML as a String.
    #
    def escape_and_replace_highlight_tags(html)
      html = ERB::Util.force_escape(html)
      html.gsub!(/#{ESCAPED_PRE_TAG}/,  "<span class='#{HIGHLIGHT_CSS_CLASSES}'>")
      html.gsub!(/#{ESCAPED_POST_TAG}/, "</span>") # rubocop:disable Rails/ViewModelHTML
      html.html_safe # rubocop:disable Rails/OutputSafety
    end

    # Takes the given string and replaces `\r` and `\r\n` with a single `\n`
    # character. Trailing whitepsace is also removed.
    #
    # str - The String to clean up.
    #
    # Returns a new string.
    #
    def cleanup_line_endings(str)
      str = str.rstrip
      str.gsub!(/\r\n?/m, "\n")
      str
    end

    # If the source code file contains our literal highlight tags, then we
    # cannot reasonably insert HTML <span> tags into the file without clobbering
    # the actual code. We simply skip the result highlighting and present a file
    # snippet instead.
    #
    def sanity_check_file_highlights!
      if file =~ /#{ESCAPED_PRE_TAG}/ || file =~ /#{ESCAPED_POST_TAG}/
        @highlights.delete("file") if has_file_highlights?
      end
    end

    def populate_results_data
      hl_path
      hl_filename

      @match_count = number_of_matches

      language = Linguist::Language.find_by_name(@language) if @language
      @language_color = language.color if language

      @repo_default_branch = @repo.default_branch

      @hl_fragments = []
      highlights.each do |highlight|
        lines = []
        highlight.each_line_with_number do |line, number|
          lines << { line: line, line_number: number }
        end
        @hl_fragments << { lines: lines }
      end
    end

    # This is a helper class that will take a highlighted search fragment and
    # apply those highlight tags to the syntax highlighted source code. It
    # will also reconcile the search fragment lines to their proper location
    # in the overall source code file.
    #
    # The two methods that should be used publicly for this class are the
    # `line_numbers` and the `each_line_with_number` methods. These allow the
    # search/syntax highlighted source code fragment to be displayed and
    # linked back to the full source code file.
    #
    class CodeHighlighter

      # Run the source code through the syntax highlighter for the given
      # language. In the event of a missing grammar, this method will just
      # return an HTML escaped version of the code.
      #
      # code     - The soruce code as a String.
      # language - The language String.
      #
      # Returns the highlighted source code as an Array of Strings.
      def self.highlight(code, language)
        scope = Linguist::Language[language].try(:tm_scope)
        if scope
          lines = GitHub::Colorize.highlight_one(scope, code, code_snippet: true)
        else
          lines = GitHub::Colorize.highlight_plain(code)
        end
        process_lines(lines)
      end

      # Post-process lines after syntax highlighting them. This mutates the
      # array of strings in place so that we don't have to make a copy
      # and then another HTML-safe copy.
      def self.process_lines(lines)
        lines.map! do |line|
          line << "\n"
        end
      end

      attr_reader :code, :esc_code, :hl_code, :language
      attr_writer :line_numbers, :lines, :dotcom_search_line_numbers
      attr_accessor :fragment, :dotcom_fragment

      # Create a new code highlighter from the given source code string,
      # highlighted source code string, and optional search fragment.
      #
      # code - The full source code file as a String.
      # opts - The options Hash
      #   :hl_code  - The full highlighted source code file as an Array of lines.
      #   :language - The language for the source code file as a String.
      #   :fragment - The search highlighted source code fragment String.
      #
      def initialize(code, opts = {})
        @code     = code
        @hl_code  = opts.fetch(:hl_code, nil)
        @language = opts.fetch(:language, nil)
        @fragment = opts.fetch(:fragment, nil)
        @dotcom_search_line_numbers = opts.fetch(:line_numbers, nil)
        @dotcom_fragment = @fragment

        @esc_code = ERB::Util.force_escape(@code) if @code
        @fragment = String.new(ERB::Util.force_escape(@fragment)) if @fragment # String.new resets html_safe? TODO: remove me, it shouldn't be needed here
      end

      # Public: This method will return the Range of line numbers in the file
      # where the search fragment is found. These are 0-based line numbers.
      #
      # Returns a Range of line numbers in the file.
      #
      def line_numbers
        return @line_numbers if defined? @line_numbers

        max_lines = esc_code.count("\n")
        @line_numbers = 0..(max_lines > 6 ? 6 : max_lines)
        return @line_numbers if fragment.nil?

        clean = fragment.gsub(/#{ESCAPED_PRE_TAG}|#{ESCAPED_POST_TAG}/, "")
        char_offset = esc_code.index(clean)
        return @line_numbers if char_offset.nil?

        start  = esc_code.slice(0, char_offset).count("\n")
        finish = start + clean.count("\n")
        finish = max_lines if finish > max_lines

        @line_numbers = start..finish
      end

      # These are the normal source code lines (no syntax highlighting). These
      # are always full line, never line fragments.
      #
      # Returns an Array of source code lines as Strings.
      #
      def lines
        return @lines if defined? @lines
        # esc_code has been HTML escaped, so the resulting Array is html_safe.
        @lines = extract_lines(esc_code, line_numbers).map! { |line| line.html_safe } # rubocop:disable Rails/OutputSafety
      end

      # These are the syntax highlighted source code lines. This method will
      # only return full lines, never line fragments. However, if the lines
      # are too long (longer than MAX_PL_FRAGMENT_SIZE) then this method
      # will return nil.
      #
      # Returns an Array of syntax highlighted lines as Strings.
      #
      def hl_lines
        return @hl_lines if defined? @hl_lines

        @hl_lines =
            # If the file was small enough to be syntax-highlighted in its
            # entirety, then extract out the matching lines from the
            # syntax-highlighted code.
            if hl_code
              hl_code[line_numbers]

            # If the file was too large to syntax-highlight it all, then
            # extract out the lines surrounding the search match and
            # syntax highlight them as a snippet.
            else
              text = extract_lines(code, line_numbers).join
              if text.size < MAX_PL_FRAGMENT_SIZE
                self.class.highlight(text, language)
              end
            end
      end

      # Returns true if we have pygments highlighted lines.
      def hl_lines?
        !hl_lines.nil?
      end

      # Returns true if we have a highlight fragment returned by
      # ElasticSearch.
      def fragment?
        !fragment.nil?
      end

      # Public: Iterate each line in the search fragment and yield the syntax
      # highlighted source code line and the corresponding line number in the
      # file. The line numbers are 0-based.
      #
      # Yields the line as a String and the Integer line number.
      #
      # Returns this CodeHighlighter instance.
      #
      def each_line_with_number
        ary = nil

        if hl_lines? && fragment?
          ary = []
          # for each search term match, insert highlight tags to accentuate
          # the search term
          matches(lines).each_with_index do |line_matches, ii|
            pos = line_matches.pop
            if line_matches.empty?
              ary[ii] = hl_lines.at(ii)
            else
              ary[ii] = insert_highlight_tags(line_matches, pos, lines.at(ii), hl_lines.at(ii))
            end
          end
        elsif fragment?
          hl = fragment.dup
          hl.gsub!(/#{ESCAPED_PRE_TAG}/,  "<span class='#{HIGHLIGHT_CSS_CLASSES}'>")
          hl.gsub!(/#{ESCAPED_POST_TAG}/, "</span>") # rubocop:disable Rails/ViewModelHTML
          ary = hl.split("\n").map! do |line|
            line << "\n"
            hl.html_safe? ? line.html_safe : line # rubocop:disable Rails/OutputSafety
          end
        else
          ary = lines.map do |line|
            truncated_line = line.slice(0, 160)
            truncated_line << "\n" unless line.end_with?("\n")
            line.html_safe? ? truncated_line.html_safe : truncated_line # rubocop:disable Rails/OutputSafety
          end
        end

        # now yield the highlighted lines one by one along with their true
        # line number in the source code file
        line_numbers.each_with_index do |number, ii|
          yield ary.at(ii), number
        end

        self
      end

      # Public: Iterate each line in the search fragment and yield the syntax
      # highlighted source code line and the corresponding line number in the
      # file. The line numbers are 0-based.
      #
      # Yields the line as a String and the Integer line number.
      #
      # Returns this CodeHighlighter instance.
      #
      def dotcom_search_each_line_with_number
        if fragment?
          ary = self.class.highlight(@dotcom_fragment, language)
          ary.each do |line|
            line.gsub!(/#{ESCAPED_PRE_TAG}/,  "<span class='#{HIGHLIGHT_CSS_CLASSES}'>")
            line.gsub!(/#{ESCAPED_POST_TAG}/, "</span>") # rubocop:disable Rails/ViewModelHTML
          end
        else
          ary = lines.map do |line|
            truncated_line = line.slice(0, 160)
            truncated_line << "\n" unless line.end_with?("\n")
            line.html_safe? ? truncated_line.html_safe : truncated_line # rubocop:disable Rails/OutputSafety
          end
        end

        # now yield the highlighted lines one by one along with their true
        # line number in the source code file
        @dotcom_search_line_numbers.each_with_index do |number, ii|
          yield ary.at(ii), number
        end

        self
      end

      # This method will extract each highlighted term from the search
      # fragment and return those terms grouped by line. So if the search
      # fragement contained 4 lines, then an Array of length 4 will be
      # returned. Each element in the returned Array is an Array of matching
      # terms.
      #
      # Returns an Array of matching terms with one entery per line in the
      # search fragment.
      #
      def matches(lines)
        rv = []

        fragment.split("\n").each_with_index do |line, ii|
          clean = line.gsub(/#{ESCAPED_PRE_TAG}|#{ESCAPED_POST_TAG}/, "")
          pos  = lines.at(ii)&.index(clean).to_i
          pos += line.index(::Search::Queries::CodeQuery::PRE_TAG).to_i

          ary = line.scan(/#{ESCAPED_PRE_TAG}(.*?)#{ESCAPED_POST_TAG}/).flatten
          ary << pos
          rv << ary
        end

        rv
      end

      # Insert highlight tags into a line of source code that has been syntax
      # highlighted by the Pygments library. The `highlight` String is
      # modified by this method. Specifically, <span></span> tags are inserted
      # into the highlight String to mark the locations of the `matches`.
      #
      # matches   - The Array of Strings to highlight.
      # pos       - The Integer position in the line where matches start.
      # line      - The source code line as a String.
      # highlight - The syntax highlighted source code line as a String.
      #
      # Returns the passed in highlight String.
      #
      def insert_highlight_tags(matches, pos, line, highlight)
        return if highlight.nil?
        # Remember so we can restore it after mutating the string.
        hl_html_safe = highlight.html_safe?
        line = line.chomp
        highlight = highlight.chomp

        ary = []
        map = position_map(highlight)

        # sanity check - return without doing anything if this check fails
        if map.length != line.length
          return hl_html_safe ? highlight.html_safe : highlight # rubocop:disable Rails/OutputSafety
        end

        matches.each do |match|
          # look for this match in the normal source code line
          pos = line.index(match, pos)
          next if pos.nil?

          # get the offsets into the syntax highlighted source code line and
          # then mark the locations of the <span> tags (taking into account the
          # existing syntax highlighting tags)
          offsets = map.slice(pos, match.length)
          ary << offsets.first

          offsets.each_cons(2) { |a, b| (ary << a + 1 << b) if (b - a) > 1 }
          ary << offsets.last + 1

          # increment our position to search for the next match
          pos += match.length
        end

        # now insert the <span> tags in reverse order (so we don't mess up our
        # offset locations)
        ary.reverse.each_slice(2) do |close, open|
          highlight.insert(close, "</span>") # rubocop:disable Rails/ViewModelHTML
          highlight.insert(open, "<span class='#{HIGHLIGHT_CSS_CLASSES}'>")
        end
        hl_html_safe ? highlight.html_safe : highlight # rubocop:disable Rails/OutputSafety
      end

      # A position map is an Array of offset locations between a plain text
      # string and the same text marked up with HTML tags. The best way to
      # explain this is by example. Imagine we have a normal string and the
      # same string but with HTML tags.
      #
      #   This is the normal string
      #
      #   <span class="hl">This<span> is the <span class="hl">normal</span> string
      #
      # The position map for these two strings will be an Array of length 25.
      # The number at position 0 in the array is the offset into the HTML
      # string of the first character in the normal string. For our example
      # above the position map would be:
      #
      #  [17, 18, 19, 20, 27, 28, 29, 30, 31, 32, 33, 34, 52, 53, 54, 55, 56, ...]
      #    T   h   i   s   _   i   s   _   t   h   e   _   n   o   r   m   a  ...
      #
      # I've put the characters below the position map to give you a better
      # idea of how this works (underscores have been substituted for spaces).
      #
      # string - The String contain the HTML markup to position map.
      #
      # Returns an Array of offsets mapping bewteen the normal and HTML strings.
      #
      def position_map(string)
        map = []
        tag = /<\/?[^>]+>/
        scanner = StringScanner.new string
        char_pos = 0

        loop do
          break if scanner.eos?

          if scanner.match? tag
            if matched = scanner.scan(tag)
              char_pos += matched.length  # skip returns bytesize which is why we can't use it
            end
          elsif str = scanner.scan(/[^<]+/)       # (good ol UTF-8)
            start_pos = char_pos
            char_pos += str.length
            map.concat((start_pos...(char_pos)).to_a)
          end
        end

        map
      end

      # Extract an Array of lines from the given string. This method will only
      # extract a contiguous range of lines from the string.
      #
      # string - The input String
      # range  - The Range of lines to extract
      #
      # Returns an Array of lines as Strings.
      #
      def extract_lines(string, range)
        lines = []
        count = 0
        match = /\n|\z/
        scanner = StringScanner.new string.scrub

        loop do
          range.include?(count) ? lines << scanner.scan_until(match) : scanner.skip_until(match)

          count += 1
          break if count > range.last || scanner.eos?
        end

        lines.compact!
        lines
      end
    end  # CodeHighlighter

    def for_frontend_rendering
      {
        id: @id,
        path: @path,
        filename: @filename,
        match_count: @match_count,
        explain: @explain,
        file_size: @file_size,
        public: @public,
        language: @language,
        language_color: @language_color,
        blob_sha: @blob_sha,
        commit_sha: @commit_sha,
        timestamp: @timestamp,
        repo_id: @repo_id,
        repo: ::Search::ResultsView::repository_for_frontend_rendering(@repo),
        repo_name: @repo_name,
        repo_default_branch: @repo_default_branch,
        owner_login: @owner_login,
        hl_path: @hl_path,
        hl_filename: @hl_filename,
        hl_fragments: @hl_fragments,
      }
    end

  end  # CodeResultView
end  # Search
