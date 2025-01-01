# typed: false
# frozen_string_literal: true

# Git unified diff parser.
#
#   parser = Parser.new("<diff text>")
#   parser.each do |entry|
#     p entry.path
#     p entry.additions
#     p entry.deletions
#     p entry.binary?
#     p entry.text
#   end
#
# See the section "GENERATING PATCHES WITH -P" in the git-diff(1) manual.
class GitHub::Diff::Parser
  class UnrecognizedText < StandardError; end

  attr_reader :truncated, :truncated_reason

  TRUNCATING_REGEX = /^Truncating diff: (.*)/

  def initialize(text)
    @truncated = false
    @state = State.new(text)
  end

  # Parse each diff entry and yield to the block.
  def each
    until @state.at_end?
      @truncated = false

      parse_diff_header

      return if @truncated

      parse_extended_headers
      parse_diff_text
      yield @entry
    end
  end

  # Parses the very first line of each file diff and creates a new Entry on
  # the instance in @entry. The diff header looks like this:
  #
  #   diff --git a/path.ext b/path.ext
  #   diff --git "a/path\rwith\"crap" "b/path\rwith\"crap"
  #
  # The a/ and b/ filenames are the same unless rename/copy is involved.
  # Especially, even for a creation or a deletion, /dev/null is not used
  # in place of the a/ or b/ filenames.
  #
  # When rename/copy is involved, file1 and file2 show the name of the
  # source file of the rename/copy and the name of the file that
  # rename/copy produces, respectively.
  #
  # Returns nothing.
  # Raises exception when no diff line is found.
  def parse_diff_header
    case
    when @state.match?(%r|^#timed_out|)
      @state.advance
      @truncated = true
      @truncated_reason = @state.copy_current_line
      if match = TRUNCATING_REGEX.match(@truncated_reason)
        @truncated_reason = match[1]
      end
      @state.advance
    when match = @state.match(%r|^diff --git (.*)$|)
      paths = match[1]
      a, b = read_paths(paths)
      @entry = GitHub::Diff::Entry.new(a, b)
      @state.advance
    when @state.match?(%r|^[0-9a-f]{40}$|)
      # root commit diff garbage, try again
      @state.advance
      parse_diff_header
    else
      line = @state.copy_current_line
      @state.advance
      fail_unrecognized!(line)
    end
  end

  # Parse extended diff header lines. These follow immediately after the
  # diff header line and may be any of the following:
  #
  #   old mode <mode>
  #   new mode <mode>
  #   deleted file mode <mode>
  #   new file mode <mode>
  #   copy from <path>
  #   copy to <path>
  #   rename from <path>
  #   rename to <path>
  #   similarity index <number>
  #   dissimilarity index <number>
  #   index <hash>..<hash> <mode>
  #
  # File modes are 6-digit octal numbers including the file type and file
  # permission bits.
  #
  # Path names in extended headers do not include the a/ and b/ prefixes.
  #
  # The similarity index is the percentage of unchanged lines, and the
  # dissimilarity index is the percentage of changed lines. It is a rounded
  # down integer, followed by a percent sign. The similarity index value of
  # 100% is thus reserved for two equal files, while 100% dissimilarity means
  # that no line from the old file made it into the new one.
  #
  # The index line includes the SHA-1 checksum before and after the change.
  # The <mode> is included if the file mode does not change; otherwise,
  # separate lines indicate the old and new mode.
  #
  # TAB, LF, double quote and backslash characters in pathnames are represented
  # as \t, \n, \" and \\, respectively. If there is need for such substitution
  # then the whole pathname is put in double quotes.
  def parse_extended_headers
    start_position = @state.position
    while !@state.at_end? && !@state.match?(/^(diff|@|Truncating)/)
      case
      when match = @state.match(%r{^--- (.+)$})
        # Git may append a trailing tab if the filename contained spaces
        @entry.a_path = normalize_path(match[1].gsub(/\t$/, ""))
      when match = @state.match(%r{^\+\+\+ (.+)$})
        # Git may append a trailing tab if the filename contained spaces
        @entry.b_path = normalize_path(match[1].gsub(/\t$/, ""))
        @state.advance
        break
      when match = @state.match(%r{^Binary files (.*) and ("?b/.*|/dev/null) differ$})
        @entry.binary = true
        @entry.a_path = normalize_path(match[1])
        @entry.b_path = normalize_path(match[2])
        @state.advance
        break
      when match = @state.match(%r{^index ([0-9a-f]+)\.\.([0-9a-f]+) (\d+)$}) || @state.match(%r{^index ([0-9a-f]+)\.\.([0-9a-f]+)$})
        @entry.a_blob, @entry.b_blob = normalize_sha1(match[1]), normalize_sha1(match[2])
        @entry.a_mode = @entry.b_mode = normalize_mode(match[3]) if match[3]
      when match = @state.match(%r{^old mode (\d+)})
        @entry.a_mode = normalize_mode(match[1])
      when match = @state.match(%r{^new mode (\d+)})
        @entry.b_mode = normalize_mode(match[1])
      when match = @state.match(%r{^deleted file mode (\d+)$})
        @entry.a_mode = normalize_mode(match[1])
        @entry.b_path = nil
        @entry.b_mode = nil
      when match = @state.match(%r{^new file mode (\d+)$})
        @entry.b_mode = normalize_mode(match[1])
        @entry.a_path = nil
        @entry.a_mode = nil
      when match = @state.match(%r{^(rename|copy) from (.+)$})
        @entry.rename_type = match[1]
        @entry.a_path = decode_path(match[2])
      when match = @state.match(%r{^(rename|copy) to (.+)$})
        @entry.rename_type = match[1]
        @entry.b_path = decode_path(match[2])
      when match = @state.match(%r{^similarity index ([\d.]+)%})
        @entry.similarity = match[1].to_i
      when match = @state.match(%r{^dissimilarity index ([\d.]+)%})
        @entry.dissimilarity = match[1].to_i
      else
        line = @state.copy_current_line
        @state.advance
        fail_unrecognized!(line)
      end

      @state.advance
    end
    @entry.extended_header_text = @state.copy(start_position, @state.position)
  end

  # Parse the diff text.
  def parse_diff_text
    case
    when @state.match?(/^@/)
      start_position = @state.position
      until @state.at_end?
        case
        when @state.match?(/\+/);    @entry.additions += 1
        when @state.match?(/-/) ;    @entry.deletions += 1
        end
        @state.advance
        break if @state.at_end? || @state.match?(/^diff|^#/)
      end
      @entry.text = @state.copy(start_position, @state.position - 1)
    when match = @state.match(/^Omitting (\d+) additions, (\d+) deletions due to (.*?) limit\./)
      @entry.additions = match[1].to_i
      @entry.deletions = match[2].to_i
      @entry.skipped_reason = match[3]
      @entry.text = nil
      @state.advance
    when match = @state.match(TRUNCATING_REGEX)
      @entry.additions = @entry.deletions = 0
      @entry.text = nil
      @entry.truncated_reason = match[1]
      @truncated = true
      @truncated_reason = match[1]
      @state.advance
    when @state.match?(/^diff|^#/) || @state.at_end?
    else
      fail_unrecognized!(@state.copy_current_line)
    end
  end

  # Internal: Reads the paths part of the diff command and extracts the two paths.
  #
  # Returns a two-element array of String paths
  def read_paths(line)
    midpoint  = line.size / 2
    midstring = line[midpoint, 4]  # 4 characters, to catch possible "

    if midstring.match(/ "?b\//)
      paths = line[0..midpoint - 1], line[midpoint + 1..-1]
    else
      paths = line.split(/\s(?="?b\/)/, 2)
    end

    paths.collect! do |path|
      if path.start_with?('"')
        de_escape_path path[3..-2]  # remove the a/ or b/ part
      else
        path[2..-1]  # remove the a/ or b/ part
      end
    end

    paths
  end

  # Normalize a 6 digit octal mode.
  #
  # Returns nil when the null mode is provided.
  def normalize_mode(mode)
    mode if mode != GitHub::NULL_MODE
  end

  # Normalize a 40 char SHA1.
  #
  # Returns nil when the null oid is provided.
  def normalize_sha1(sha1)
    sha1 if sha1 != GitHub::NULL_OID
  end

  # Decode path and perform some basic conversions: turns /dev/null into a
  # literal nil and strips the a/ or b/ prefix.
  #
  # Returns the new path as a String.
  def normalize_path(path)
    return nil if path == "/dev/null"
    path = decode_path(path)
    path = path[2..-1] if path.start_with?("a/", "b/")
    path
  end

  # Special escape characters used in encoded git paths.
  ESCAPE = {
    '\a' => "\a",
    '\b' => "\b",
    '\f' => "\f",
    '\n' => "\n",
    '\r' => "\r",
    '\t' => "\t",
    '\v' => "\v",
    '\"' => '"',
    "\\\\" => "\\",
  }

  # Decode special (\n, \r, etc) and octal sequences (\NNN) in diff path names.
  # No decoding is performed unless the path is quoted.
  def decode_path(path)
    return path unless path.start_with?('"')
    de_escape_path path[1...-1]
  end

  def de_escape_path(path)
    path.gsub /\\(?:\d{3}|[abfnrtv"\\])/n do |match|
      match = match.to_s
      ESCAPE[match] || match[1..-1].to_i(8).chr
    end
  end

  private

  # An unrecognized line was encountered, log it to splunk and send a redaction message to sentry.
  def fail_unrecognized!(line)
    correlation_id = SecureRandom.urlsafe_base64(18)
    GitHub.logger.info(
      "Unrecognized line encountered",
      "code.namespace" => "GitHub::Diff::Parser",
      "code.function" => "fail_unrecognized",
      "gh.diff.line" => line,
      "gh.correlation_id" => correlation_id
    )
    fail UnrecognizedText, "text redacted, see splunk correlation_id=#{correlation_id}"
  end

  class State
    def initialize(text)
      @scanner = StringScanner.new(text)
    end

    def at_end?
      @scanner.eos?
    end

    def copy(first, last)
      if last
        @scanner.string.byteslice(first, last - first)
      else
        @scanner.string.byteslice(first)
      end
    end

    def copy_current_line
      return if at_end?
      newline = @scanner.string.index("\n", position)
      copy(position, newline)
    end

    def advance
      return if at_end?
      @scanner.skip_until(/\n/)
      nil
    end

    def position
      @scanner.pos
    end

    # Does the regex match the string at the current position?
    def match?(regex)
      !!match(regex)
    end

    # Attempt to match the string at the current position.
    #
    # On success, returns an object that responds to `#[n]` to retrieve the
    # N-th subgroup in the match. On failure, returns nil.
    def match(regex)
      return if at_end?

      # StringScanner allows access to match data via `#[]`
      @scanner if @scanner.match?(regex)
    end
  end
end
