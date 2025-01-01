# typed: true
# frozen_string_literal: true

require "iopromise/data_loader"

# Interface to Git blame information for an individual file. A 'blame' shows
# each line of the file along with information on the last commit that modified
# that line.
#
# TODO: The blame reading, parsing, and caching should be moved to GitRPC/Rugged.
class Blame
  include Enumerable
  include IOPromise::DataLoader

  # This is also defined in `GitRPC::Client::Blame` - we can't directly use this
  # there because GitRPC doesn't necessarily have access to Rails' models.
  IGNORE_REVS_FILE_PATH = ".git-blame-ignore-revs"

  # Can be raised when trying to blame an invalid path
  NoCommitsAtPath = Class.new(StandardError)

  # Public: The Repository this Blame is bound to.
  attr_reader :repository

  # Public: The commit oid string representing the version to start at. A
  # commit must exist in repository for this oid.
  attr_reader :commit_oid

  # Public: The full path to the tree entry to blame. This path must exist at
  # the given commit oid and must identify a blob object.
  attr_reader :path

  # Public: Create a new Blame for a given commit and path.
  #
  # repository   - The Repository object where the blame should be performed.
  # commit_oid   - The commit oid string of the version to start at.
  # path         - The full path to the tree entry to blame.
  # line_numbers - An optional array of line numbers to scope the blame to.
  # since        - An optional date to filter returned blame by.
  # timeout      - Timeout to pass to gitrpc
  # skip_cache   - Skips fetching and setting the blame cache
  #
  # This object typically isn't created directly. Use Repository#blame() instead.
  def initialize(repository, commit_oid, path, line_numbers: [], since: nil, timeout: nil, incremental: false, skip_cache: false)
    if commit_oid.to_s.size != 40
      raise ArgumentError, "Invalid oid: #{commit_oid.inspect}"
    end
    @repository = repository
    @path = path
    @commit_oid = commit_oid.to_s
    @lines = nil
    @line_numbers = line_numbers
    @since = since
    @timeout = timeout
    @incremental = incremental
    @skip_cache = skip_cache
  end

  # Public: Access the blame line structures as an array.
  #
  # Returns an array of structure arrays. Each line is represented as an
  # array with members: [lineno, oldlineno, commit, text, reblame_path].
  def lines
    @lines ||= to_a
  end

  # Public: Read blame output from cache or remote git call and associate
  # Commit objects for each line efficiently. Yields for each logical blame
  # output line:
  #
  #   yield lineno, oldlineno, commit, text, reblame_path
  #
  # Returns self.
  def each(&block)
    # establish commit object for each line from our batch list
    line_data.each do |lineno, old_lineno, commit_oid, text, reblame_path|
      commit = commits[commit_oid]
      yield lineno, old_lineno, commit, text, reblame_path
    end
  end

  # Determine if the file being blamed has any lines in it.
  #
  # Returns true if the file has zero lines.
  def empty?
    line_data.empty?
  end

  # currently backwards compatible with the old sync version below (short circuits)
  attr_async :last_commit_oid, -> do
    T.bind(self, Blame)

    return Promise.resolve.then { last_commit_oid } if defined?(@last_commit_oid)

    repository.rpc.async_paged_commits_log(commit_oid, max_count: 1, path: path).then do |log|
      @last_commit_oid = log.first
      @last_commit_oid or raise NoCommitsAtPath
    end
  end

  # Deprecated version of async version above.
  def last_commit_oid
    @last_commit_oid = repository.rpc.paged_commits_log(commit_oid, max_count: 1, path: path).first unless defined?(@last_commit_oid)
    @last_commit_oid or raise NoCommitsAtPath
  end

  def commits
    @commits ||= begin
      # build a list of distinct commit oids and read in a single call
      oids = Set.new
      line_data.each do |_, _, commit_oid, _|
        oids << commit_oid
      end
      repository.commits.find(oids.to_a).index_by(&:oid)
    end
  end

  # Pretty object inspection
  def inspect
    %Q{#<Blame "#{path} <#{commit_oid}>">}
  end

  # Internal: Reads the blame output from cache or remote git access.
  attr_async :line_data, -> do
    T.bind(self, Blame)

    fetch_and_parse_blame = -> do
      fetch_blame = repository.rpc.async_blame(
        commit_oid,
        path,
        annotate: @line_numbers,
        since: @since,
        timeout: @timeout,
        ignore_revs_file: has_ignore_revs_file?,
        incremental: @incremental
      )
      fetch_blame.then { |out| parse_blame_output(out) }
    end

    blame_data =
      if @skip_cache
        fetch_and_parse_blame.call
      else
        # TODO: remove cast when sorbet understands `attr_async`
        T.cast(self, T.untyped).async_last_commit_oid.then do # preloads this, then `blame_cache_key` uses it
          GitHub.cache.async_get_or_cache(blame_cache_key, stats_key: "blame.async_load") do
            fetch_and_parse_blame.call
          end
        end
      end

    blame_data = blame_data.rescue do |ex|
      case ex
      when GitRPC::NoSuchPath, GitRPC::BadLineRange, NoCommitsAtPath
        []
      when GitRPC::Timeout
        Failbot.report(ex)
        []
      else
        raise ex
      end
    end

    # since we are preloading the data async, we need to store it as well so that the sync version (below)
    # uses the result. without this, we rely on the GitHub.cache (thread-local), which doesn't cache failures.
    blame_data.then do |result|
      @line_data = result
    end
  end

  # Deprecated version of async version above.
  def line_data
    @line_data ||= read_blame_data
  end

  def with_cache(&block)
    if @skip_cache
      block.call
    else
      GitHub.cache.fetch(blame_cache_key) do
        block.call
      end
    end
  end

  def read_blame_data(retry_without_ignore_revs: true, ignore_revs_file: has_ignore_revs_file?)
    with_cache do
      out = repository.rpc.blame(commit_oid, path, annotate: @line_numbers, since: @since, timeout: @timeout, ignore_revs_file:, incremental: @incremental)
      parse_blame_output(out)
    end
  rescue GitRPC::NoSuchPath, GitRPC::BadLineRange, NoCommitsAtPath
    []
  rescue GitRPC::Timeout => e
    Failbot.report(e)
    if ignore_revs_file && retry_without_ignore_revs
      @ignore_revs_failed = true
      out = repository.rpc.blame(commit_oid, path, annotate: @line_numbers, since: @since, timeout: @timeout, ignore_revs_file: false, incremental: @incremental)
      parse_blame_output(out)
    else
      raise GitRPC::Timeout
    end
  end

  def blame_cache_key
    cache_key = "v2:#{last_commit_oid}:#{Digest::SHA256.hexdigest(path)}".dup

    if @line_numbers.any?
      cache_key << ":#{Digest::SHA256.hexdigest(@line_numbers.join(","))}"
    end

    if @since
      cache_key << ":#{@since.to_i}"
    end

    if has_ignore_revs_file?
      cache_key << ":#{ignore_revs_file_oid}"
    end

    "blame:v4:#{repository.network_cache_key}:#{cache_key}"
  end

  # Internal: Parses `git-blame --porcelain` output into an array of line
  # information structures - one per line.
  #
  # output - String output from `git blame --porcelain'.
  #
  # Returns an Array of structured arrays for each line. Lines are represented
  #   as an Array with members: [lineno, oldlineno, commit_oid, text,
  #   reblame_path].
  def parse_blame_output(output)
    lines = []
    info = {}
    blame_cache = {}
    boundary = T.let(false, T::Boolean)
    commit_oid = T.let(nil, T.nilable(String))
    old_line_number = T.let(nil, T.nilable(Integer))
    line_number = T.let(nil, T.nilable(Integer))

    output.to_s.split("\n").each do |line|
      if line[0, 1] == "\t"
        if boundary
          boundary = false
          next
        end

        lines << line[1, line.size]
        info[line_number] = [
          commit_oid,
          old_line_number,
          blame_cache.fetch(commit_oid, {})[:reblame_path],
        ]
      elsif m = /^previous \w{40} (.+$)/.match(line)
        commit_cache = blame_cache[commit_oid] ||= {}
        commit_cache[:reblame_path] = m[1]
      elsif m = /^(\w{40}) (\d+) (\d+)/.match(line)
        commit_oid, old_line_number, line_number = m[1], m[2].to_i, m[3].to_i
      elsif @since && line == "boundary"
        # When filtering by date if the line was last changed before the specified date
        # it will be treated as a boundary commit - record that so we can filter these out.
        boundary = true
      end
    end

    info.sort.map do |lineno, (commit_oid, old_lineno, reblame_path)|
      [lineno, old_lineno, commit_oid, lines[lineno - 1], reblame_path]
    end
  end

  def has_ignore_revs_file?
    ignore_revs_file_oid.present?
  end

  def ignore_revs_file_oid
    @ignore_revs_file_oid ||= begin
      repository.rpc.read_tree_entry_oid(commit_oid, IGNORE_REVS_FILE_PATH)
    rescue GitRPC::NoSuchPath
      nil
    end
  end

  def did_blame_with_ignore_revs_timeout?
    @ignore_revs_failed
  end
end
