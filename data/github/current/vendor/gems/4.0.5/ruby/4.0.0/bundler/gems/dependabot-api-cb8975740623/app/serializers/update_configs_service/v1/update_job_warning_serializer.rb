# frozen_string_literal: true

module UpdateConfigsService
  module V1
    class UpdateJobWarningSerializer < ActiveModel::Serializer
      attributes :id,
                 :type,
                 :title,
                 :description

      def warning_presenter
        @warning_presenter ||= object.warning_presenter
      end

      def type
        warning_presenter.issue_type
      end

      def title
        warning_presenter.issue_title
      end

      def description
        warning_presenter.issue_body
      end
    end
  end
end
