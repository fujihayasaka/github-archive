# typed: true
# frozen_string_literal: true

module PullRequests::PageData::Diffs::Contents::AmbiguousCharacterDetection
  include GitHub::Memoizer
  # Determines if a diff line has added ambiguous characters (homoglyphs).
  #
  # This method checks if an addition line contains ambiguous Unicode characters
  # that were not present in the related line (typically a deletion). Homoglyphs
  # are characters that look similar but have different Unicode codepoints,
  # which can be used maliciously to disguise code changes.
  #
  # The method only processes addition lines and compares them against their
  # related lines (if any) to detect newly introduced ambiguous characters.
  #
  # @param line [GitHub::Diff::Line] The diff line to analyze
  # @return [Boolean] true if the line is an addition that introduces new
  #   ambiguous characters not present in the related line, false otherwise
  #
  # @example Addition line with homoglyphs and no related line
  #   line = GitHub::Diff::Line.new(type: :addition, text: "text\u2028")
  #   has_added_ambiguous_characters?(line) #=> true
  #
  # @example Addition line with ambiguous characters but related line also has them
  #   related = GitHub::Diff::Line.new(type: :deletion, text: "old\u2028")
  #   line = GitHub::Diff::Line.new(type: :addition, text: "new\u2028")
  #   line.related_line = related
  #   has_added_ambiguous_characters?(line) #=> false
  #
  # @example Non-addition line
  #   line = GitHub::Diff::Line.new(type: :deletion, text: "text\u2028")
  #   has_added_ambiguous_characters?(line) #=> false
  sig { params(line: GitHub::Diff::Line, pull_request: PullRequest, repository: T.nilable(Repository)).returns(T::Boolean) }
  def has_added_ambiguous_characters?(line:, pull_request:, repository:)
    return false unless line.type == :addition

    GitHub.instrument("diff.has_added_ambiguous_characters") do
      GitHub.dogstats.time("diff", tags: ["action:detect_ambiguous_characters", "type:single_line"]) do
        overlap = (Set.new(line.text.codepoints) & ambiguous_characters)
        line_has_ambiguous_characters = overlap.any?
        related_line_has_ambiguous_characters = T.let(false, T::Boolean)

        if line_has_ambiguous_characters
          related_line_has_ambiguous_characters = !!(line.related_line && (Set.new(line.related_line.text.codepoints) & ambiguous_characters).any?)
        end

        has_added_ambiguous_characters = line_has_ambiguous_characters && !related_line_has_ambiguous_characters
        if has_added_ambiguous_characters
          GitHub.logger.info(
            "Detecting ambiguous characters in diff line",
            "code.function" => "has_added_ambiguous_characters",
            "gh.catalog_service" => "github/pull_requests",
            "gh.pull_request.id" => pull_request.id,
            "gh.pull_request.url" => pull_request.url,
            "gh.repository.id" => repository&.id,
            "gh.repository.nwo" => repository&.name_with_display_owner,
            "gh.repository.private" => repository&.private?,
            "ambiguous_character_detected" => codepoint_to_unicode(overlap),
          )
        end
        has_added_ambiguous_characters
      end
    end
  end

  sig { params(overlapping_codepoints: Set).returns(String) }
  private def codepoint_to_unicode(overlapping_codepoints)
    overlapping_codepoints.to_a.pack("U*")
  end

  memoize def ambiguous_characters
    # This set of codepoints for ambiguous characters is extracted from https://github.com/hediet/vscode-unicode-data/blob/main/out/ambiguous.json
    # Contains ambiguous character codepoints from all language configurations.
    # Homoglyphs are characters that can look similar to other characters and may be used maliciously.
    file_path = Rails.root.join("config/diffs/ambiguous-characters.json")
    data = JSON.parse(File.read(file_path))

    Set.new(data["ambiguous_characters"]).freeze
  rescue Errno::ENOENT => e
    GitHub.logger.error("Ambiguous characters config file not found: #{file_path}")
    Set.new.freeze
  rescue JSON::ParserError => e
    GitHub.logger.error("Invalid JSON in ambiguous characters config: #{e.message}")
    Set.new.freeze
  rescue StandardError => e
    GitHub.logger.error("Error loading ambiguous characters: #{e.message}")
    Set.new.freeze
  end
end
