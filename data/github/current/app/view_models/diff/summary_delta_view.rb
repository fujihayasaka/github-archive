# typed: true
# frozen_string_literal: true

module Diff
  class SummaryDeltaView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include UrlHelper
    include GitHub::UTF8

    delegate :added?, :removed?, :copied?, :renamed?, :deleted?, :status_label,
      :additions, :deletions, :binary?, :changes, to: :delta

    def initialize(summary_delta)
      @delta = summary_delta
    end

    attr_reader :delta

    def anchor
      return @anchor if defined?(@anchor)
      @anchor = diff_file_anchor(path)
    end

    def formatted_diffstat(width = 5)
      DiffHelper.format_diffstat_line(delta, width)
    end

    def a_path
      return @a_path if defined? @a_path

      @a_path = utf8(delta.old_file.path)
    end

    def b_path
      return @b_path if defined? @b_path

      @b_path = utf8(delta.new_file.path)
    end

    def unknown_changes?
      binary? || (changes == 0 && !renamed?)
    end

    def path
      b_path
    end

    def simple_rename?
      delta.renamed? && delta.similarity == 100
    end

    def octicon
      name = delta.status_label == "changed" ? "modified" : delta.status_label
      "diff-#{name}"
    end
  end
end
