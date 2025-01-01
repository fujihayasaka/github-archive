# typed: true
# frozen_string_literal: true

module Storage

  class NotImplementedError < ::NotImplementedError
  end

  class ReplicationError < StandardError
    def initialize(replicas = nil)
      replicas ||= GitHub.storage_replica_count
      super("could not find #{replicas} online replicas")
    end
  end

  def self.policy_creator
    @policy_creator ||= ::Storage::PolicyCreator.new(
      Avatar,
      Marketplace::ListingScreenshot,
      Marketplace::ListingImage,
      OauthApplicationLogo,
      Releases::Public.storage_interface,
      RepositoryFile,
      RepositoryImage,
      UploadManifestFile,
      UserAsset,
      MigrationFile,
      OctoshiftMigrationArchive,
      EnterpriseInstallationUserAccountsUpload,
      CodeqlDatabase,
      CodeqlVariantAnalysisRepoTask,
      GitHubModels::Attachment,
      Copilot::ChatAttachment
    )
  end

  def self.not_implemented!(policy, uploadable, method)
    raise NotImplementedError, "#{uploadable.class} does not implement #{policy.class}##{method}"
  end
end
