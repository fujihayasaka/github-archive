# frozen_string_literal: true

# Utility class to ensure directories are transformed/presented consistently
class Directories
  include Enumerable

  class IndeterminateOverlapError < StandardError; end

  GLOB_SPECIAL_CHARACTERS = %w(* ? [ ] { }).freeze
  GLOB_REGEX = Regexp.new("[#{GLOB_SPECIAL_CHARACTERS.map { |char| Regexp.escape(char) }.join}]")

  DONT_MATCH_SLASHES = File::FNM_PATHNAME
  MATCH_DOT_FILES    = File::FNM_DOTMATCH

  def initialize(*directories)
    # Store glob status before homogenization removes escape characters
    @original_patterns = [*directories].flatten.map(&:to_s)
    @directories = homogenize(*directories)
    freeze
  end

  def each(&block)
    directories.each(&block)
  end

  def ==(other)
    to_a == other.to_a
  end
  alias eql? ==

  def hash
    [self.class, to_a].hash
  end

  def overlap?(*directory_patterns_or_globs)
    other = if directory_patterns_or_globs.first.is_a?(self.class)
              directory_patterns_or_globs.first
            else
              self.class.new(*directory_patterns_or_globs)
            end

    if contains_glob? && other.contains_glob?
      # use heuristics to determine if the directories overlap
      return false unless prefix_overlap?(directories, other)

      # If after using heuristics we can't tell if the directories overlap,
      # raise an error to indicate that overlap is indeterminate.
      raise IndeterminateOverlapError
    end

    homogenized_patterns = other.to_a

    directories.any? do |dir|
      homogenized_patterns.any? do |potential_match|
        match?(dir, potential_match)
      end
    end
  end

  # similar to overlap? but does not take a glob as a parameter
  def cover?(*directory_patterns)
    raise ArgumentError, "Directories#cover? does not accept globs" if directory_patterns.any? do |dir|
                                                                         # Only reject obvious glob patterns
                                                                         # like * wildcards
                                                                         # Allow literal directories that contain
                                                                         # other special chars
                                                                         dir.include?("*")
                                                                       end

    other = if directory_patterns.first.is_a?(self.class)
              directory_patterns.first
            else
              self.class.new(*directory_patterns)
            end

    homogenized_patterns = other.to_a

    directories.any? do |dir|
      homogenized_patterns.any? do |potential_match|
        File.fnmatch?(dir, potential_match, DONT_MATCH_SLASHES | MATCH_DOT_FILES)
      end
    end
  end

  def contains_glob?
    @original_patterns.any? { |pattern| glob?(pattern) }
  end

  private

  attr_reader :directories, :original_patterns

  def glob?(pattern)
    (0...pattern.length).each do |index|
      char = pattern[index]
      return true if GLOB_SPECIAL_CHARACTERS.include?(char) && (index.zero? || pattern[index - 1] != "\\")
    end

    false
  end

  def homogenize(*directories)
    directories = [*directories].flatten

    directories.inject(Set.new) do |collection, dir|
      # Remove escape characters to get the literal directory name
      unescaped_dir = dir.to_s.gsub(/\\([*?\[\]{}])/, '\1')

      collection.add(
        unescaped_dir.
        sub(%r{/*\Z}, "").   # remove trailing slashes
        sub(%r{\A/*}, "/").  # prefix with a single slash
        sub(%r{\A/\Z}, "/.") # use `/.` as root
      )
    end.sort
  end

  def match?(left_hand_side, right_hand_side)
    File.fnmatch?(left_hand_side, right_hand_side, DONT_MATCH_SLASHES | MATCH_DOT_FILES) ||
      File.fnmatch?(right_hand_side, left_hand_side, DONT_MATCH_SLASHES | MATCH_DOT_FILES)
  end

  # Two globs cannot overlap unless they share a common prefix. This method returns
  # true if the directories share a common prefix, and false otherwise.
  # If they do share a common prefix, they still may not overlap, but if they do
  # not share a common prefix, they definitely do not overlap.
  def prefix_overlap?(directories, other)
    left_prefixes = directories.map { |dir| dir.split(GLOB_REGEX).first }
    right_prefixes = other.to_a.map { |dir| dir.split(GLOB_REGEX).first }

    left_prefixes.any? { |prefix| right_prefixes.any? { |other_prefix| prefix.start_with?(other_prefix) } } ||
      right_prefixes.any? { |prefix| left_prefixes.any? { |other_prefix| prefix.start_with?(other_prefix) } }
  end
end
