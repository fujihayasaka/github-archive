# typed: true
# frozen_string_literal: true

module Stafftools
  module Users
    class AttachmentsListComponent < ApplicationComponent
      sig { params(attachments: T.any(ActiveRecord::Relation, T::Array[T.any(UserAsset, RepositoryFile)]), actor: ::User, target_user: ::User, attachments_type: Symbol).void }
      def initialize(attachments:, actor:, target_user:, attachments_type:)
        @attachments = attachments
        @actor = actor
        @target_user = target_user
        @attachments_type = attachments_type
      end

      private

      attr_reader :attachments, :attachments_type, :target_user, :actor

      def attachments_type_pretty
        case @attachments_type
        when :user_assets
          "user assets"
        when :repository_files
          "repository files"
        end
      end

      def form_id(deletion_type)
        "#{dialog_id(deletion_type)}_form"
      end

      def dialog_id(deletion_type)
        dialog_id = "delete-#{@attachments_type}"
        "#{dialog_id}-#{deletion_type}"
      end
    end
  end
end
