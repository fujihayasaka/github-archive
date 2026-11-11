# typed: true
# frozen_string_literal: true

module Stafftools
  module Users
    class AttachmentsBatchDeleteDialogComponent < ApplicationComponent
      sig { params(deletion_type: Symbol, target_user: ::User, attachments_type: Symbol, dialog_id: String, form_id: String).void }
      def initialize(deletion_type:, target_user:, attachments_type:, dialog_id:, form_id:)
        @deletion_type = deletion_type
        @attachments_type = attachments_type
        @target_user = target_user
        @dialog_id = dialog_id
        @form_id = form_id
      end

      private

      attr_reader :attachments_type, :target_user, :dialog_id, :deletion_type, :form_id

      def title
        case @deletion_type
        when :all
          "Delete all #{attachments_type_pretty}"
        when :selected
          "Delete selected #{attachments_type_pretty}"
        end
      end

      def attachments_type_pretty
        case @attachments_type
        when :user_assets
          "user assets"
        when :repository_files
          "repository files"
        end
      end
    end
  end
end
