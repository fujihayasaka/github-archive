# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class AttachmentImporter < Importer
      include GitHub::Migrator::TarUtils

      def import(attributes, options = {})
        attachment = Attachment.new do |attachment|
          attachable_key = %w[
            discussion
            issue
            pull_request
            issue_comment
            commit_comment
            pull_request_review
            pull_request_review_comment
          ].find { |attachable_key| attributes.has_key?(attachable_key) }

          attachable = model_from_source_url!(attributes[attachable_key])
          attachable = attachable.issue if attachable.is_a?(PullRequest)

          attachment.attachable = attachable
          attachment.attacher = model_from_source_url!(attributes["user"]) || User.ghost
          attachment.entity = attachable.repository
          attachment.created_at = attributes["created_at"]

          asset_path =
            begin
              T.must(URI.parse(attributes["asset_url"]).path)[1..-1]
            rescue URI::InvalidURIError => e
              attributes.fetch("asset_url").sub(%r{\Atarball://root/}, "")
            end
          raise_on_unsupported_asset!(asset_path)
          read_from_archive(asset_path) do |file|
            asset = UserAssetExtendedContentTypes.new
            asset.uploader = attachment.attacher
            asset.repository_id = attachable.repository.id
            asset.name = attributes["asset_name"]
            asset.user_id = asset.user_id.nil? ? attachment.attacher_id : asset.user_id

            asset_file = ActionDispatch::Http::UploadedFile.new({
              filename: attributes["asset_name"],
              tempfile: file,
              type: attributes["asset_content_type"],
            })
            attachment.asset = import_asset(asset, asset_file)
          end
        end

        ImporterResult.new(
          import_model(attachment)
        )
      rescue GitHub::Migrator::AssociationFailed => error
        log_and_create_importer_result(
          attributes,
          error,
          "Skipped import: failed to find model associated with attachment",
          "attachment",
          "skipped"
        )
      rescue ActiveRecord::NotNullViolation,
             ActiveRecord::RecordInvalid => error
        log_and_create_importer_result(
          attributes,
          error,
          "Skipped import: invalid or missing attachment",
          "attachment",
          "skipped"
        )
      rescue GitHub::Storage::Uploader::Error,
        ::Storage::Policy::HttpError => error
        log_and_create_importer_result(
          attributes,
          error,
          "Skipped import: attachment upload failed",
          "attachment",
          "skipped"
        )
      rescue GitHub::Migrator::UnsupportedUploadableAsset => error
        log_and_create_importer_result(
          attributes,
          error,
          "Skipped import: unsupported uploadable asset",
          "attachment",
          "skipped"
        )
      end

      class UserAssetExtendedContentTypes < ::UserAsset
        include ::Storage::Uploadable
        set_content_types \
          "application/pdf" => ".pdf",
          "application/vnd.openxmlformats-officedocument.wordprocessingml.document" => ".docx",
          "application/vnd.openxmlformats-officedocument.presentationml.presentation" => ".pptx",
          "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" => ".xlsx",
          "application/vnd.oasis.opendocument.text" => %w(.odt .fodt),
          "application/vnd.oasis.opendocument.spreadsheet" => %w(.ods .fods),
          "application/vnd.oasis.opendocument.presentation" => %w(.odp .fodp),
          "application/vnd.oasis.opendocument.graphics" => %w(.odg .fodg),
          "application/vnd.oasis.opendocument.formula" => ".odf",
          "application/vnd.ms-excel" => %w(.csv .xls),
          "application/zip" => ".zip",
          "application/x-zip-compressed" => ".zip",
          "application/gzip" => ".gz",
          "application/x-gzip" => ".gz",
          "text/plain" => %w(.csv .txt .patch),
          "text/x-log" => ".log",
          "image/gif"  => ".gif",
          "image/jpeg" => %w(.jpg .jpeg),
          "image/png"  => ".png",
          "text/csv"   => ".csv",
          "text/comma-separated-values" => ".csv",
          "application/csv" => ".csv",
          "application/excel" => ".csv",
          "application/vnd.msexcel" => ".csv",
          "text/markdown" => ".md",
          "video/quicktime" => ".mov",
          "video/mp4" => %w(.mp4 .mov)
      end
    end
  end
end
