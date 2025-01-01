# typed: true
# frozen_string_literal: true

# This class knows how to parse `git grep` output and turn it into discrete
# hashes of easily-consumed information. This is somewhat complex with extra
# surrounding lines of context are desired, and becomes more so when the
# "function" (hunk header) gets added.
#
# In the sample input that follows, grep results are separated into chunks with
# lines consisting of `--` (two dashes). Each line has a marker surrounding the
# line number, and the marker can be one of three characters:
#
# `:` - the matching line
# `-` - a context line
# `=` - the "function" (hunk header) context line
#
# If the function context line falls within the surrounding context, it remains
# a single chunk. Otherwise, the function context line appears as a one-line chunk
# before the result-with-context chunk.
#
# This sample input:
#
#   app/models/organization.rb-781-  # The team of administrators for this organization. They have all the power.
#   app/models/organization.rb=782=  def owners_team
#   app/models/organization.rb:783:    backscatter_deprecate_method if direct_org_membership_enabled?
#   app/models/organization.rb-784-
#   app/models/organization.rb-785-    if !defined? @owners_team
#   --
#   app/models/repository.rb=2595=  def fork(options = {})
#   --
#   app/models/repository.rb-2598-    # actually, formally deprecate this argument
#   app/models/repository.rb-2599-    if !forker && options[:owner]
#   app/models/repository.rb:2600:      backscatter_deprecate_method(message: "use :forker instead of :owner")
#   app/models/repository.rb-2601-      new_owner = forker = options[:owner]
#   app/models/repository.rb-2602-    end
#   --
#   app/models/repository/refs_dependency.rb=116=  def master_branch
#   --
#   app/models/repository/refs_dependency.rb-121-      # under Rails 3.
#   app/models/repository/refs_dependency.rb-122-      backscatter_measure
#   app/models/repository/refs_dependency.rb:123:      backscatter_deprecate_method
#   app/models/repository/refs_dependency.rb-124-    end
#   app/models/repository/refs_dependency.rb-125-
#   --
#   app/models/repository/refs_dependency.rb=134=  def master_branch=(val)
#   --
#   app/models/repository/refs_dependency.rb-138-      # https://github.com/github/github/pull/22598
#   app/models/repository/refs_dependency.rb-139-      backscatter_measure
#   app/models/repository/refs_dependency.rb:140:      backscatter_deprecate_method
#   app/models/repository/refs_dependency.rb-141-    end
#   app/models/repository/refs_dependency.rb-142-
#   --
#   app/models/repository/refs_dependency.rb=287=  def master_sha
#   app/models/repository/refs_dependency.rb-288-    backscatter_measure
#   app/models/repository/refs_dependency.rb:289:    backscatter_deprecate_method
#   app/models/repository/refs_dependency.rb-290-
#   app/models/repository/refs_dependency.rb-291-    default_oid
#   --
#   app/models/team.rb=387=  def owners?
#   app/models/team.rb-388-    if organization.present? && organization.direct_org_membership_enabled?
#   app/models/team.rb:389:      backscatter_deprecate_method
#   app/models/team.rb-390-    end
#   app/models/team.rb-391-
#   --
#   app/models/user.rb-1920-
#   app/models/user.rb=1921=  def fork(repository)
#   app/models/user.rb:1922:    backscatter_deprecate_method(message: "use repo.fork(:forker => user) instead")
#   app/models/user.rb-1923-
#   app/models/user.rb-1924-    return [false, :organization] if organization?
#   --
#   lib/github/backscatter.rb=101=    def backscatter_trace(sample_rate = nil)
#   --
#   lib/github/backscatter.rb-113-    # Returns nil.  Raises GitHub::Backscatter::DeprecationError when
#   lib/github/backscatter.rb-114-    # `backscatter_fatal_deprecations?` is true (e.g., in development or testing).
#   lib/github/backscatter.rb:115:    def backscatter_deprecate_method(message: nil)
#   lib/github/backscatter.rb-116-      return unless GitHub.backscatter_enabled?
#   lib/github/backscatter.rb-117-      emit_deprecation_warning(message)
#   --
#   lib/github/backscatter.rb=169=    def called_method_details
#   --
#   lib/github/backscatter.rb-179-    end
#   lib/github/backscatter.rb-180-
#   lib/github/backscatter.rb:181:    # Public: do `backscatter_deprecate_method` calls raise GitHub::Backscatter::DeprecationError ?
#   lib/github/backscatter.rb-182-    #
#   lib/github/backscatter.rb-183-    # Returns true if exceptions will be raised, false otherwise.  Defaults to
#   --
#   lib/github/backscatter.rb-192-
#   lib/github/backscatter.rb=193=    def self.deprecations
#   lib/github/backscatter.rb:194:      @deprecations ||= GitHub::Grep.new.code_use "backscatter_deprecate_method",
#   lib/github/backscatter.rb-195-        dirs: %w[app jobs lib]
#   lib/github/backscatter.rb-196-    end
#
# will produce this sample output:
#
#   [
#     {
#       :filename   => "app/models/organization.rb",
#       :first_line => 781,
#       :last_line  => 785,
#       :code       => "  # The team of administrators for this organization. They have all the power.\n  def owners_team\n    backscatter_deprecate_method if direct_org_membership_enabled?\n\n    if !defined? @owners_team\n",
#       :context    => nil
#     },
#     {
#       :filename   => "app/models/repository.rb",
#       :first_line => 2598,
#       :last_line  => 2602,
#       :code       => "    # actually, formally deprecate this argument\n    if !forker && options[:owner]\n      backscatter_deprecate_method(message: \"use :forker instead of :owner\")\n      new_owner = forker = options[:owner]\n    end\n",
#       :context    => { :line => "  def fork(options = {})\n", :lineno => 2595 }
#     },
#     {
#       :filename   => "app/models/repository/refs_dependency.rb",
#       :first_line => 121,
#       :last_line  => 124,
#       :code       => "      # under Rails 3.\n      backscatter_measure\n      backscatter_deprecate_method\n    end\n",
#       :context    => { :line => "  def master_branch\n", :lineno => 116 }
#     },
#     {
#       :filename   => "app/models/repository/refs_dependency.rb",
#       :first_line => 138,
#       :last_line  => 141,
#       :code       => "      # https://github.com/github/github/pull/22598\n      backscatter_measure\n      backscatter_deprecate_method\n    end\n",
#       :context    => { :line => "  def master_branch=(val)\n", :lineno => 134 }
#     },
#     {
#       :filename   => "app/models/repository/refs_dependency.rb",
#       :first_line => 287,
#       :last_line  => 291,
#       :code       => "  def master_sha\n    backscatter_measure\n    backscatter_deprecate_method\n\n    default_oid\n",
#       :context    => nil
#     },
#     {
#       :filename   => "app/models/team.rb",
#       :first_line => 387,
#       :last_line  => 390,
#       :code       => "  def owners?\n    if organization.present? && organization.direct_org_membership_enabled?\n      backscatter_deprecate_method\n    end\n",
#       :context    => nil
#     },
#     {
#       :filename   => "app/models/user.rb",
#       :first_line => 1921,
#       :last_line  => 1924,
#       :code       => "  def fork(repository)\n    backscatter_deprecate_method(message: \"use repo.fork(:forker => user) instead\")\n\n    return [false, :organization] if organization?\n",
#       :context    => nil
#     }
#   ]
#
# Note the absence of results from "lib/github/backscatter.rb". This is assuming
# this parser is called from that file. See the ignore-file logic, below.

module GitHub
  class Grep

    def initialize
      @caller_file = caller_locations[0]&.absolute_path
    end

    def code_use(*patterns, dirs:, ignore: nil)
      ignore = ignore_file_list(ignore)

      # Convert RegExp objects to Strings.
      pattern_args = patterns.flat_map { |pattern| ["-e", pattern.respond_to?(:source) ? pattern.source : pattern] }

      args = %w[
        --no-index
        --line-number
        --extended-regexp
        --word-regexp
        --context=2
        --show-function
      ]

      cmd = ["git", "grep", *args, *pattern_args, "--", *dirs]

      chunks = IO.popen(cmd).read.split(/^--\n/)

      # remove any chunks from ignored files
      if ignore.present?
        chunks = chunks.reject do |chunk|
          filename, _ = chunk.lines.first.split(/[=:-]/, 2)
          ignore.include?(filename)
        end
      end

      chunks = combine_function_chunks(chunks)

      # turn the chunks into hashes
      chunks.map do |chunk|
        files, linenos, lines = chunk.lines
          .map { |l| l.split(/[=:-]/, 3) }
          .select { |l| l.length == 3 } # Ignore lines that don't match with 3 parts (e.g. binary files)
          .transpose
        filename = files.first

        context, lines, linenos = function_context(lines, linenos)
        lines, linenos = trim_blank_lines(lines, linenos)

        {
          filename: filename,
          first_line: linenos.first.to_i,
          last_line: linenos.last.to_i,
          code: lines.join(""),
          context: context,
        }
      end
    end

    private

    def ignore_file_list(files)
      this_file   = Pathname.new(__FILE__)
      caller_file = Pathname.new(@caller_file)
      caller_dir  = Dir[caller_file.to_s.chomp(caller_file.extname) + "/*"]

      related_files = (caller_dir + [caller_file, this_file]).collect do |f|
        Pathname.new(f).relative_path_from(Rails.root).to_s
      end

      Array(files) + related_files
    end

    # combine any separate-chunk "function" hunks into the following
    # chunk, so that the entire context for a grep result is in one chunk
    def combine_function_chunks(chunks)
      return chunks unless chunks.length > 1

      combined = T.let(false, T::Boolean)

      # the [nil] is to keep the last chunk from being dropped if it doesn't get combined
      chunks = (chunks + [nil]).each_cons(2).collect do |a, b|
        if combined
          combined = false
          next
        end

        if a.lines.length == 1
          combined = true
          [a, b].join("")
        else
          combined = false
          [a, b]
        end
      end.compact.collect { |x| Array(x).first }

      chunks
    end

    def function_context(lines, linenos)
      # If there are more than 5 lines, that means "function" hunk context was
      # added to this chunk. Take it back out and turn it into a line/lineno hash.
      context = if lines.length > 5
        { line: lines.shift, lineno: linenos.shift.to_i }
      end

      [context, lines, linenos]
    end

    def trim_blank_lines(lines, linenos)
      2.times do
        [lines, linenos].each(&:shift) if lines.first.blank?
        [lines, linenos].each(&:pop)   if lines.last.blank?
      end

      [lines, linenos]
    end

  end
end
