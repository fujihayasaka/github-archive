# typed: false
# frozen_string_literal: true

module GitHub
  class Migrator
    class ReleaseImporter < Importer
      include GitHub::Migrator::TarUtils

      def import(attributes, options = {})
        release = Release.new do |release|
          release.repository = \
            model_from_source_url!(attributes["repository"])
          release.author = user_or_fallback(attributes["user"])

          release.name             = attributes["name"]
          release.tag_name         = attributes["tag_name"]
          release.body             = attributes["body"]
          release.state            = attributes["state"]
          release.pending_tag      = attributes["pending_tag"]
          release.prerelease       = attributes["prerelease"]
          release.target_commitish = attributes["target_commitish"]
          release.published_at     = attributes["published_at"]
          release.created_at       = attributes["created_at"]
        end

        release = import_model(release)

        attributes["release_assets"].each do |asset_attributes|
          asset_path = URI.parse(asset_attributes["asset_url"]).path[1..-1]
          raise_on_unsupported_asset!(asset_path)
          read_from_archive(asset_path) do |file|
            release_asset = release.release_assets.new
            release_asset.uploader = release.author
            release_asset.label = asset_attributes["label"]
            release_asset.name = asset_attributes["name"]
            release_asset.guid = asset_attributes["guid"]

            release_file = ActionDispatch::Http::UploadedFile.new({
              filename: asset_attributes["name"],
              tempfile: file,
              type: asset_attributes["content_type"],
            })

            import_asset(release_asset, release_file)
          end
        rescue GitHub::Migrator::UnsupportedUploadableAsset => error
          GitHub.logger.error("Skipped import: unsupported uploadable asset", {
            :exception => error,
            "code.function" => "import",
            "code.namespace" => "GitHub::Migrator::ReleaseImporter",
            "gh.migration_tools.migration.type" => "repo",
            "gh.migration_tools.migration.model.name" => "release_asset",
            "gh.migration_tools.migration.model.source_url" => attributes["url"],
            "gh.migration_tools.migration.model.resolution" => "skipped"
          }
        )
          next
        end

        release
      rescue GitHub::Storage::Uploader::Error,
        ::Storage::Policy::HttpError => error
        GitHub.logger.error("Skipped import", {
          :exception => error,
          "code.function" => "import",
          "code.namespace" => "GitHub::Migrator::ReleaseImporter",
          "gh.migration_tools.migration.type" => "repo",
          "gh.migration_tools.migration.model.name" => "release",
          "gh.migration_tools.migration.model.source_url" => attributes["url"],
          "gh.migration_tools.migration.model.resolution" => "skipped"
         }
        )

        nil
      end
    end
  end
end
