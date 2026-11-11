# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::UserNotices
  class Payload
    class Notice < T::Struct
      const :name, String
      const :dismissed, T::Boolean
    end

    sig do
      params(
        notices: T::Array[PullRequests::PageData::UserNotices::Loader::Notice]
      ).returns(T::Array[Notice])
    end
    def self.call(notices)
      notices.map do |notice|
        Notice.new(
          name: notice.name,
          dismissed: notice.dismissed
        )
      end
    end
  end
end
