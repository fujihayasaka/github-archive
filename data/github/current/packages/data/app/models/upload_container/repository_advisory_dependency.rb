# typed: strict
# frozen_string_literal: true

module UploadContainer
  module RepositoryAdvisoryDependency
    extend T::Helpers
    extend ActiveSupport::Concern

    abstract!

    sig { void }
    def assign_upload_container_id_to_user_assets
      urls = Storage::UserAssetTransfer::RepositoryAdvisoryAssetBackfiller.extract_urls_from_text(T.cast(self, RepositoryAdvisory).description)
      return if urls.empty?
      actor_id = GitHub.context[:actor_id]
      return unless actor_id.present?
      actor = User.find(actor_id)
      return unless actor.present?
      Storage::UserAssetTransfer::RepositoryAdvisoryAssetBackfiller.backfill_upload_container_ids(T.cast(self, RepositoryAdvisory), actor, urls)
    end

    sig { void }
    def assign_upload_container_id_to_file_attachments
      urls = Storage::RepositoryFileTransfer::RepositoryAdvisoryRepositoryFileBackfiller.extract_urls_from_text(T.cast(self, RepositoryAdvisory).description)
      return if urls.empty?
      actor_id = GitHub.context[:actor_id]
      return unless actor_id.present?
      actor = User.find(actor_id)
      return unless actor.present?
      Storage::RepositoryFileTransfer::RepositoryAdvisoryRepositoryFileBackfiller.backfill_upload_container_ids(T.cast(self, RepositoryAdvisory), actor, urls)
    end
  end
end
