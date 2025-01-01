# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class AttachmentSerializer < BaseSerializer

      def as_json(options = {})
        {
          :type               => "attachment",
          :url                => url,
          :legacy_url         => legacy_url,
          target_symbol       => target,
          :user               => user,
          :asset_name         => asset_name,
          :asset_content_type => asset_content_type,
          :asset_url          => asset_url,
          :created_at         => created_at,
        }
      end

      private

      def url
        model.asset.storage_external_url
      end

      def legacy_url
        model.asset.legacy_storage_external_url
      end

      def target_symbol
        if model.attachable_type == "Issue" && model.attachable.pull_request.present?
          "pull_request"
        else
          model.attachable_type.underscore
        end.to_sym
      end

      def target
        url_for_association(model, :attachable)
      end

      def user
        url_for_association(model, :attacher)
      end

      def asset
        model.asset
      end

      def asset_name
        asset.name
      end

      def asset_content_type
        asset.content_type
      end

      def asset_url
        "tarball://root/attachments/#{asset.guid}/#{asset.name}"
      end
    end
  end
end
