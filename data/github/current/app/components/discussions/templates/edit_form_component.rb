# typed: true
# frozen_string_literal: true

module Discussions
  module Templates
    class EditFormComponent < ApplicationComponent
      include UploadHelper

      delegate :spamurai_form_signals, to: :helpers

      def initialize(
        data_issue_url:,
        data_mention_url:,
        data_preview_url:,
        logged_in:,
        repository:,
        user:,
        resource:
      )
        @data_issue_url = data_issue_url
        @data_mention_url = data_mention_url
        @data_preview_url = data_preview_url
        @logged_in = logged_in
        @repository = repository
        @user = user
        @resource = resource
      end

      private

      attr_reader(
        :data_issue_url,
        :data_mention_url,
        :data_preview_url,
        :repository,
        :user,
        :resource
      )

      def render?
        logged_in?
      end

      def logged_in?
        @logged_in
      end

      def file_attachment_tag(**args, &block)
        UploadHelper.instance_method(:file_attachment_tag).bind(self).call(**args, &block)
      end
    end
  end
end
