# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::UserNotices
  class Loader
    include GitHub::ResilienceMixin

    class Notice < T::Struct
      const :name, String
      const :dismissed, T::Boolean
    end

    class Data < T::Struct
      const :notices, T::Array[Notice]
    end

    sig do
      params(
        current_user: T.nilable(User)
      ).returns(Data)
    end
    def self.load(current_user:)
      new(current_user:).load
    end

    sig do
      params(
        current_user: T.nilable(User)
      ).void
    end
    def initialize(current_user:)
      @current_user = current_user
    end

    sig { returns(Data) }
    def load
      Data.new(
        notices: build_notices
      )
    end

    private

    sig { returns(T::Array[Notice]) }
    def build_notices
      return [] unless @current_user

      with_database_error_fallback(fallback: []) do
        single_file_notice = Notice.new(
          name: UserNotice::SINGLE_FILE_MODE_NOTICE,
          dismissed: @current_user.dismissed_notice?(UserNotice::SINGLE_FILE_MODE_NOTICE)
        )

        opt_out_notice = T.let(nil, T.nilable(Notice))
        unless @current_user.has_feature_preview_enrollment_record?(:prx_files)
          opt_out_notice = Notice.new(
            name: UserNotice::FILES_CHANGED_OPT_OUT_NOTICE,
            dismissed: @current_user.dismissed_notice?(UserNotice::FILES_CHANGED_OPT_OUT_NOTICE)
          )
        end

        # Don't include compact_diff_lines_notice if opt_out_notice exists and is not dismissed
        compact_diff_lines_notice = T.let(nil, T.nilable(Notice))
        if opt_out_notice.nil? || opt_out_notice.dismissed
          compact_diff_lines_notice = Notice.new(
            name: UserNotice::COMPACT_DIFF_LINES_NOTICE,
            dismissed: @current_user.dismissed_notice?(UserNotice::COMPACT_DIFF_LINES_NOTICE)
          )
        end

        modern_header_notice = T.let(nil, T.nilable(Notice))
        if @current_user.feature_flag_enabled?(:updated_pull_request_header, default: false)
          modern_header_notice = Notice.new(
            name: UserNotice::PULL_REQUEST_MODERN_HEADER_NOTICE,
            dismissed: @current_user.dismissed_notice?(UserNotice::PULL_REQUEST_MODERN_HEADER_NOTICE)
          )
        end

        [compact_diff_lines_notice, single_file_notice, opt_out_notice, modern_header_notice].compact
      end
    end
  end
end
