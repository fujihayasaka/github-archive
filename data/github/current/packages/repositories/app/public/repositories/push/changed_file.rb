# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Repositories
  module Push
    class ChangedFile
      include GitHub::Memoizer

      # https://git-scm.com/docs/git-diff#_raw_output_format
      ADDITION = "A"
      DELETION = "D"
      RENAMING = "R"
      MODIFYING = "M"
      TYPE = "T"
      UNKNOWN = "?"
      ALLOWED_TYPES = [ADDITION, DELETION, RENAMING, MODIFYING, TYPE, UNKNOWN]

      attr_reader :repository, :ref, :previous_oid, :oid

      BigExtensions = Set.new(%w(.dmg .rpm .tar .gz .deb .zip .gz .bz2 .exe .msi .iso))

      def initialize(repository: nil, ref: nil, previous_oid: nil, oid: nil, change_type: nil, path: nil, previous_path: nil, score: 0)
        @repository = repository
        @ref = ref
        @previous_oid = previous_oid
        @oid = oid
        @change_type = change_type
        @path = quote(path)
        @previous_path = quote(previous_path)
        @score = score
      end

      alias sha oid
      alias before previous_oid

      memoize def previous_path
        return if deletion? || modifying? || type?

        @previous_path
      end

      memoize def path
        if deletion?
          @previous_path
        else
          @path
        end
      end

      memoize def change_type
        if renaming?
          sprintf "%c%03d", RENAMING, @score
        elsif ALLOWED_TYPES.include?(@change_type)
          @change_type
        else
          UNKNOWN
        end
      end

      def change_type_symbol
        case
        when addition?
          :ADDITION
        when deletion?
          :DELETION
        when renaming?
          :RENAME
        when modifying?
          :MODIFICATION
        else
          :UNKNOWN
        end
      end

      def addition?
        ADDITION == @change_type
      end

      def deletion?
        DELETION == @change_type
      end

      def renaming?
        RENAMING == @change_type
      end

      def modifying?
        MODIFYING == @change_type
      end

      def type?
        TYPE == @change_type
      end

      def big?
        sha != GitHub::NULL_OID &&
          BigExtensions.include?(File.extname(path.to_s))
      end

      private

      SPECIAL_QUOTES = {
        0x07 => "\\a",
        0x08 => "\\b",
        0x09 => "\\t",
        0x0A => "\\n",
        0x0B => "\\v",
        0x0C => "\\f",
        0x0D => "\\r",
        0x22 => "\\\"",
        0x5C => "\\\\",
      }

      def quote(path_to_quote)
        # Skip paths that aren't set.
        return path_to_quote if path_to_quote.nil?
        # All paths should be binary (ASCII-8BIT) here. If not, assume the caller knows what's up and just return the encoded path_to_quote.
        return path_to_quote if path_to_quote.encoding != Encoding::ASCII_8BIT

        # Quote like git's quote.c quotes.
        # See also git-config(1), core.quotePath.
        # https://github.com/github/git/blob/6d6d3e03a821719a2424bd379573e91c17d6d5fe/quote.c
        needs_quotes = T.let(false, T::Boolean)
        res = path_to_quote.bytes.map do |b|
          case
          when spec = SPECIAL_QUOTES[b]
            needs_quotes = true
            spec
          when b < 0x20 || b >= 0x7f
            needs_quotes = true
            sprintf("\\%03o", b)
          else
            b.chr
          end
        end
        if needs_quotes
          (['"'] + res + ['"']).join.b
        else
          path_to_quote
        end
      end
    end
  end
end
