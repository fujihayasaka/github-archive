# typed: true
# frozen_string_literal: true

# Public: Parser for different output formats of `git diff-tree`.
class GitRPC::Diff::DiffTreeParser
  # This regular expression matches the output of `git diff-tree -z --raw`
  RAW_MATCHER = %r{
    :
    (?<old_mode>\d{6})\s
    (?<new_mode>\d{6})\s
    (?<old_oid>[a-zA-Z0-9]{40})\s
    (?<new_oid>[a-zA-Z0-9]{40})\s
    (?:
      (?<status>[CR])
      (?<similarity>\d{3})
      \x00(?<src_path>[^\x00]+)\x00(?<dst_path>[^\x00]+)\x00
      |
      (?<status>[M])
      (?<similarity>\d{3})?
      \x00(?<src_path>[^\x00]+)\x00
      |
      (?<status>[ADTUX])
      \x00(?<src_path>[^\x00]+)\x00
    )
  }x

  # This regular expression matches the output of `git diff-tree -z --numstat`
  NUMSTAT_MATCHER = %r{
    (?<additions>\d+|\-)\t
    (?<deletions>\d+|\-)\t
    (
      (?<src_path>[^\x00]+)\x00
      |
      \x00(?<src_path>[^\x00]+)\x00(?<dst_path>[^\x00]+)\x00
    )
  }x

  # This regular expression matches the output of `git diff-tree -z --shortstat`
  SHORTSTAT_MATCHER = %r{
    \s(?<files_changed>\d+)\sfiles?\schanged
    (,\s(?<insertions>\d+)\sinsertions?\(\+\))?
    (,\s(?<deletions>\d+)\sdeletions?\(\-\))?
  }x

  # Maximum number of files that we will parse deltas for
  MAX_FILES = 3_000

  def initialize(input)
    @scanner = StringScanner.new(input)
  end

  # Public: parse the input and return a summary object
  #
  # Returns a GitRPC::Diff::Summary representation of the input data
  def parse_summary
    deltas = parse_summary_deltas

    return GitRPC::Diff::Summary.empty if deltas.empty?

    totals = parse_shortstat

    GitRPC::Diff::Summary.new(
      additions:     totals[:insertions],
      deletions:     totals[:deletions],
      changed_files: totals[:files_changed],
      deltas:        deltas
    )
  end

  # Public: parse the input and return an array of deltas
  #
  # Returns a array of GitRPC::Diff::Delta objects
  def parse_deltas
    delta_hashes = parse_raw_output
    build_deltas(GitRPC::Diff::Delta, delta_hashes)
  end

  private

  attr_reader :scanner

  # Internal: Parse `--raw` output into a list of hashes.
  #
  # These hashes contain all the information required to build
  # `GitRPC::Diff::Delta` objects.
  def parse_raw_output
    delta_hashes = []

    skip_commit_id

    while scanner.scan(RAW_MATCHER)
      delta_hashes << {
        status: scanner["status"],
        similarity: scanner["similarity"] && scanner["similarity"].to_i,
        old_file: {
          oid: scanner["old_oid"],
          mode: scanner["old_mode"],
          path: scanner["src_path"]
        },
        new_file: {
          oid: scanner["new_oid"],
          mode: scanner["new_mode"],
          path: scanner["dst_path"] || scanner["src_path"]
        }
      }
    end

    delta_hashes
  end

  # Internal: Parse `--numstat` output into a list of delta hashes.
  #
  # Extends the given list of delta hashes with `additions`
  # and `deletions` information.
  def parse_numstat_output_into(delta_hashes)
    delta_hashes.each do |delta|
      next if scanner.match?(NUMSTAT_MATCHER) && delta.dig(:old_file, :path) != scanner["src_path"]
      scanner.scan(NUMSTAT_MATCHER)

      delta[:additions] = parse_addition_or_deletion(scanner["additions"])
      delta[:deletions] = parse_addition_or_deletion(scanner["deletions"])
    end
  end

  # Internal: Skip a single 40 character SHA1 followed by a NUL byte.
  #
  # When running a diff tree against the root commit, the oid of the commit is
  # prepended to the output. This line skips that oid, if it is there.
  #
  # Example Output:
  # > git diff-tree -z -r --full-index -M -l400 --root b25eca9738dc195b312db47f38f9228ecee5042d
  # b25eca9738dc195b312db47f38f9228ecee5042d\x00:000000 100644 0000000000000000000000000000000000000000 61e2c47c2586f58135995994fd793da0d4627776 A\x00name
  def skip_commit_id
    scanner.skip(/[a-zA-Z0-9]{40}\x00/)
  end

  def parse_summary_deltas
    delta_hashes = parse_raw_output
    parse_numstat_output_into(delta_hashes)

    build_deltas(GitRPC::Diff::Summary::Delta, delta_hashes)
  end

  def build_deltas(delta_class, delta_hashes)
    deltas = delta_hashes.each_with_index.each_with_object([]) do |(hash, index), result|
      break result if index == MAX_FILES

      if hash[:status] == "T"
        result << delta_class.new(**delta_hash_for_deletion(hash)).freeze
        result << delta_class.new(**delta_hash_for_addition(hash)).freeze
      else
        result << delta_class.new(**hash).freeze
      end
    end
    deltas.freeze
  end

  # Parse `--shortstat` output
  def parse_shortstat
    scanner.scan(SHORTSTAT_MATCHER)

    {
      insertions:    scanner["insertions"].to_i,
      deletions:     scanner["deletions"].to_i,
      files_changed: scanner["files_changed"].to_i
    }
  end

  def parse_addition_or_deletion(addition_or_deletion)
    addition_or_deletion == "-" ? nil : addition_or_deletion.to_i
  end

  def delta_hash_for_addition(delta_hash)
    delta_hash = delta_hash.dup
    delta_hash[:old_file] = delta_hash[:old_file].dup

    delta_hash[:status] = "A"
    delta_hash[:similarity] = 0
    delta_hash[:old_file][:oid] = GitRPC::NULL_OID
    delta_hash[:old_file][:mode] = GitRPC::NULL_MODE

    if delta_hash.key?(:additions) || delta_hash.key?(:deletions)
      delta_hash[:deletions] = delta_hash[:additions].nil? ? nil : 0
    end

    delta_hash
  end

  def delta_hash_for_deletion(delta_hash)
    delta_hash = delta_hash.dup
    delta_hash[:new_file] = delta_hash[:new_file].dup

    delta_hash[:status] = "D"
    delta_hash[:similarity] = 0
    delta_hash[:new_file][:oid] = GitRPC::NULL_OID
    delta_hash[:new_file][:mode] = GitRPC::NULL_MODE

    if delta_hash.key?(:additions) || delta_hash.key?(:deletions)
      delta_hash[:additions] = delta_hash[:deletions].nil? ? nil : 0
    end

    delta_hash
  end
end
