# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::ThreadPreviewPositioning
  class Payload
    class DiffLine < T::Struct
      const :html, T.nilable(String)
      const :left, T.nilable(Integer)
      const :right, T.nilable(Integer)
      const :text, T.nilable(String)
      const :type, String
    end

    class PositionedThreadData < T::Struct
      const :commitOid, T.nilable(String)
      const :diffLines, T::Array[DiffLine]
      const :endDiffSide, T.nilable(String)
      const :endLine, T.nilable(Integer)
      const :path, T.nilable(String)
      const :startDiffSide, T.nilable(String)
      const :startLine, T.nilable(Integer)
      const :isOutdated, T::Boolean
    end

    sig do
      params(
        positioned_threads: T::Array[Loader::PositionedThread]
      ).returns(T::Hash[Integer, PositionedThreadData])
    end
    def self.call(positioned_threads)
      positioned_threads.each_with_object({}) do |positioned_thread, hash|
        diff_lines = positioned_thread.diff_lines.map do |diff_line|
          DiffLine.new(
            html: diff_line[:html],
            left: diff_line[:left],
            right: diff_line[:right],
            text: diff_line[:text],
            type: diff_line[:type].to_s.upcase
          )
        end

        hash[positioned_thread.thread_id] = PositionedThreadData.new(
          commitOid: positioned_thread.commit_oid,
          diffLines: diff_lines,
          endDiffSide: positioned_thread.end_diff_side,
          endLine: positioned_thread.end_line,
          path: positioned_thread.path,
          startDiffSide: positioned_thread.start_diff_side,
          startLine: positioned_thread.start_line,
          isOutdated: positioned_thread.is_outdated
        )
      end
    end
  end
end
