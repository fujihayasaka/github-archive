# frozen_string_literal: true

module UpdateConfigsService
  module V1
    class ErrorSerializer < ActiveModel::Serializer
      attributes :id,
                 :type,
                 :msg,
                 :details

      def type
        object.error_type
      end

      def msg
        object.error_presenter.issue_title
      end

      def details
        object.error_presenter.issue_body
      end
    end
  end
end
