# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class ReleaseSerializer < BaseSerializer
      def scope
        Release.preload(:release_assets, :repository, :author, release_assets: [:uploader])
      end

      def as_json(options = {})
        {
          type: "release",
          url: url,
          repository: repository,
          user: user,
          name: name,
          tag_name: tag_name,
          body: body,
          state: state,
          pending_tag: pending_tag,
          prerelease: prerelease,
          target_commitish: target_commitish,
          release_assets: release_assets,
          reactions: reactions,
          published_at: published_at,
          created_at: created_at,
        }
      end

      private

      delegate :name, :tag_name, :body, :pending_tag, :prerelease,
        :target_commitish, to: :model

      def repository
        url_for_model(model.repository)
      end

      def user
        url_for_model(model.user)
      end

      def state
        model.state
      end

      def release_assets
        model.release_assets.uploaded.map do |release_asset|
          {
            user: url_for_model(release_asset.uploader),
            name: release_asset.name,
            content_type: release_asset.content_type,
            size: release_asset.size,
            guid: release_asset.guid,
            state: release_asset.state.to_sym,
            label: release_asset.label,
            asset_url: asset_url(release_asset),
          }
        end
      end

      def reactions
        model.reactions.map do |reaction|
          {
            user: url_for_model(reaction.user),
            content: reaction.content,
            subject_type: reaction.subject_type,
            created_at: time(reaction.created_at)
          }
        end
      end

      def published_at
        time(model.published_at)
      end

      def asset_url(release_asset)
        "tarball://root/releases/#{release_asset.guid}/#{release_asset.name}"
      end
    end
  end
end
