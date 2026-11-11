# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class AttachmentArchiver < BaseArchiver

      # Public: Save asset for an attachment.
      #
      # attachment - Attachment instance.
      def save(attachment)
        save_asset(attachment.asset)
      end

      private

      def asset_namespace
        "attachments"
      end

      def logger_fn
        "gh-migrator-save-attachment-asset"
      end
    end
  end
end
