# typed: true
# frozen_string_literal: true

class Commit
  class DiffStats
    def initialize(diff)
      @diff = diff
    end

    def files_added
      calculate_file_stats unless defined?(@files_added)
      @files_added
    end

    def files_deleted
      calculate_file_stats unless defined?(@files_deleted)
      @files_deleted
    end

    def files_modified
      diff.count
    end

    def lines_added
      diff.additions
    end

    def lines_deleted
      diff.deletions
    end

    def lines_added_by_language
      calculate_language_breakdown unless defined?(@lines_added_by_language)
      @lines_added_by_language
    end

    def lines_deleted_by_language
      calculate_language_breakdown unless defined?(@lines_deleted_by_language)
      @lines_deleted_by_language
    end

    private

    attr_reader :diff

    def calculate_file_stats
      @files_added = 0
      @files_deleted = 0

      diff.each do |entry|
        if entry.a_path.nil?
          @files_added += 1
        elsif entry.b_path.nil?
          @files_deleted += 1
        end
      end
    end

    def calculate_language_breakdown
      @lines_added_by_language = Hash.new(0)
      @lines_deleted_by_language = Hash.new(0)

      diff.each do |entry|
        next if entry.text.nil?

        file_path = entry.b_path || entry.a_path

        diff_lines_by_prefix = Hash.new { |h, k| h[k] = [] }
        entry.text.lines.each_with_object(diff_lines_by_prefix) do |line, grouped|
          prefix, code = line[0], line[1..]
          grouped[prefix] << code
        end

        if added_lang = detect_language(file_path, diff_lines_by_prefix["+"])
          @lines_added_by_language[added_lang.name] += entry.additions
        end

        if deleted_lang = detect_language(file_path, diff_lines_by_prefix["-"])
          @lines_deleted_by_language[deleted_lang.name] += entry.deletions
        end
      end
    end

    def detect_language(file_path, lines)
      blob = Linguist::Blob.new(file_path, lines.join)
      Linguist.detect(blob)
    end
  end
end
