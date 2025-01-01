# typed: strict
# frozen_string_literal: true

module UploadContainer
  module GistDependency
    extend T::Sig
    extend T::Helpers
    extend ActiveSupport::Concern

    include UploadContainerDependency

    abstract!

    sig { abstract.returns(T::Array[TreeEntry]) }
    def sorted_files; end

    included do
      T.bind(self, T.class_of(Gist))
      after_create :assign_upload_container_id_to_user_assets
    end

    sig { void }
    def assign_upload_container_id_to_user_assets
      return if GitHub.multi_tenant_enterprise?

      files_text = self.sorted_files
        .reject(&:binary?)
        .map(&:async_raw_data)
        .map(&:value)
        .join("")

      urls = Storage::UserAssetTransfer::GistAssetBackfiller.extract_urls_from_text(files_text)
      return if urls.empty?

      actor_id = GitHub.context[:actor_id]
      return unless actor_id.present?

      actor = User.find(actor_id)
      return unless actor.present?

      Storage::UserAssetTransfer::GistAssetBackfiller.backfill_upload_container_ids(T.cast(self, Gist), actor, urls)
    end

    sig { override.params(user_id: Integer, guid: String, use_new_url: T::Boolean).returns(String) }
    def private_asset_url(user_id, guid, use_new_url)
      return "#{GitHub.gist_url}/user-attachments/assets/#{guid}" if use_new_url
      "#{GitHub.gist_url}/assets/#{user_id}/#{guid}"
    end
  end
end
