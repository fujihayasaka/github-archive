# typed: true
# frozen_string_literal: true

require "gitrpc/util"
require "strscan"

module GitRPC
  # Parses the output of `git-merge-tree --no-messages -z`
  class MergeTreeConflictsParser
    def initialize(output)
      @ss = StringScanner.new(output)
    end

    class ParseError < RuntimeError; end

    class ConflictTriple
      attr_reader :base, :ours, :theirs

      def initialize(*args)
        if args.size == 1
          args = args[0]
        end
        @base = args[0] || ConflictRecord.empty
        @ours = args[1] || ConflictRecord.empty
        @theirs = args[2] || ConflictRecord.empty
      end

      def to_h
        {
          ancestor: base.to_h,
          ours: ours.to_h,
          theirs: theirs.to_h
        }
      end

    end

    class ConflictRecord
      attr_reader :mode, :oid, :path

      def initialize(mode, oid, path)
        @mode = mode
        @oid = oid
        @path = path
        @empty = false
      end

      def self.empty
        @empty_singleton ||= new(nil, nil, nil).empty!
      end

      def empty?
        @empty
      end

      def to_h
        if empty?
          nil
        else
          {
            path: path,
            oid: oid,
            mode: mode
          }
        end
      end

      # Internal:
      #
      # Marks this instance as empty; as a convenience, returns self.
      def empty!
        @empty = true
        self
      end
    end

    # Returns Array[ConflictTriple] or raises ParseError
    def parse
      # TOTAL HACK: For `merge-ort`, some conflicts look like multiple conflicts
      # e.g. when a type change is involved. This can result in stages seemingly
      # out of order.
      #
      # To accommodate for that, we defer creating conflict records until after
      # we've finished scanning the input. Example:
      #
      # 120000 HASH 3  whatever
      # 100644 HASH 1  whatever
      # 100644 HASH 2  whatever
      #
      # In this instance, seeing the stage 1 would suggest to start a new conflict
      # triplet, but because it's the same path, we should add it to the existing
      # triplet.
      #
      # NOTE! We can _only_ do this here because we currently prevent `merge-ort`
      # from detecting renames, and we _also_ force it to pick a single merge base
      # instead of performing a full recursive merge.
      #
      # A more robust solution will not parse the `ls-files`-style part of the
      # output, but the messages part.
      conflicts = Hash.new { [] }
      if !@ss.scan(/[0-9a-f]{40}(?:[0-9a-f]{24})?\0/)
        fail ParseError, "expected merge output to start with tree hash (#{@ss.peek(65).each_char.to_a}...)"
      end
      loop do
        if @ss.eos?
          fail ParseError, "unexpected end of input"
        end
        break if @ss.peek(1) == "\0"
        stage, record = parse_stage
        conflicts[record.path] = conflicts[record.path].tap do |conflict|
          conflict[stage - 1] = record
        end
      end
      conflicts.values.map do |records|
        ConflictTriple.new(records)
      end
    end

    private

    def parse_stage
      mode = consume(/\d{6}/)
      consume(" ")
      oid = consume(/[a-f0-9]{40}(?:[0-9a-f]{24})?/)
      consume(" ")
      stage = consume(/\d/)
      consume("\t")
      consume(/([^\0]+)\0/)
      path = @ss.captures[0].force_encoding("UTF-8")
      return Integer(stage), ConflictRecord.new(Integer(mode, 8), oid, path)
    end

    def consume(pattern)
      token = @ss.scan(pattern)
      return token if token
      if @ss.eos?
        fail ParseError, "unexpected end of input"
      else
        fail ParseError, "expected #{pattern.inspect} at pos #{@ss.pos} (#{@ss.peek(10).each_char.to_a}...)"
      end
    end
  end
end
