# typed: true
# frozen_string_literal: true

module Stafftools
  module Users
    class AttachmentsTableComponent < ApplicationComponent
      sig { params(attachments: T.any(ActiveRecord::Relation, T::Array[T.any(UserAsset, RepositoryFile)]), actor: ::User, target_user: ::User, attachments_type: Symbol, form_id: String).void }
      def initialize(attachments:, actor:, target_user:, attachments_type:, form_id:)
        @attachments = attachments
        @actor = actor
        @target_user = target_user
        @selected_attachments_type = attachments_type
        @form_id = form_id
      end

      private

      attr_reader :attachments, :actor, :form_id

      def is_selected_user_assets?
        @selected_attachments_type == :user_assets
      end

      sig { params(attachments_type: Symbol).returns(T::Hash[Symbol, String]) }
      def tab_attributes(attachments_type)
        is_selected = attachments_type == @selected_attachments_type

        {
          href: stafftools_user_attachments_path(@target_user, attachments_type: attachments_type),
          selected: is_selected,
          test_selector: "#{is_selected ? "selected-tab-#{attachments_type}" : ""}"
        }
      end

      def table_cell_repository_association(attachment)
        if attachment.repository.present?
          link_to(
            attachment.repository.name_with_owner,
            stafftools_repository_path(attachment.repository.owner, attachment.repository)
          )
        else
          "N/A"
        end
      end

      def table_cell_download_link(attachment)
        download_url = is_selected_user_assets? ? attachment.source_url(actor: actor) : attachment.redirect_url(actor: actor)
        link_to("Download", download_url, target: "_blank")
      end
    end
  end
end
