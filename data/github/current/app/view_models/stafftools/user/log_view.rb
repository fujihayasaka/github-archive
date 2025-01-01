# typed: true
# frozen_string_literal: true

module Stafftools
  module User
    class LogView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      attr_reader :user

      def page_title
        "#{user.login} - Activity Log"
      end

      def log_notes
        @log_notes ||= begin
          github = ::User.find_by_login("github")
          conditions = github ? ["user_id = ?", github.id] : []
          user.staff_notes.where(conditions).order("created_at DESC").to_a
        end
      end

      def log_notes?
        log_notes.any?
      end

      def comments_classes
        "comment-holder"
      end

      def comment_classes(comment)
        classes = %w(content-body markdown-body)
        if fmt = comment.try(:formatter)
          classes << "#{fmt}-format"
        end
        classes.join " "
      end

    end
  end
end
