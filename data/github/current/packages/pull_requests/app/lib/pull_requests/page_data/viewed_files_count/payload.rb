# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::ViewedFilesCount
  class Payload
    class ViewedFilesCountPayload < T::Struct
      const :viewedFilesCount, Numeric
    end

    sig do
      params(
        viewed_files_count: Numeric
      ).returns(ViewedFilesCountPayload)
    end
    def self.call(viewed_files_count)
      new.call(viewed_files_count)
    end

    sig do
      params(
        viewed_files_count: Numeric
      ).returns(ViewedFilesCountPayload)
    end
    def call(viewed_files_count)
      ViewedFilesCountPayload.new(
        viewedFilesCount: viewed_files_count,
      )
    end
  end
end
