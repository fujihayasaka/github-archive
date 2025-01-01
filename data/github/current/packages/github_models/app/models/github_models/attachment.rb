# typed: true
# frozen_string_literal: true

class GitHubModels::Attachment < ApplicationRecord::Domain::GitHubModels
  include GitHub::Validations
  include Storage::Uploadable
  include GitHubModels::AzureBlobStorageAttachmentDependency

  self.table_name = "models_attachments"

  SIZE_LIMIT_IN_MEGABYTES = 10

  set_content_types :images
  set_uploadable_policy_path "models-attachments"

  belongs_to :uploader, class_name: "::User"

  before_validation :set_guid, on: :create

  validates_inclusion_of :content_type, in: allowed_content_types
  validate :extension_matches_content_type
  validates_inclusion_of :size, in: 1..SIZE_LIMIT_IN_MEGABYTES.megabytes,
    message: "File is too big. <span class='drag-and-drop-error-info'><span class='btn-link'>Try again</span> " \
      "with a file size less than #{SIZE_LIMIT_IN_MEGABYTES}MB.</span>"
  validates_presence_of :uploader, on: :create
  validates_presence_of :name
  validates :name, unicode3: true
  validate :storage_ensure_inner_asset

  before_destroy :storage_delete_object

  enum :state, Storage::Uploadable::STATES
  attribute :guid, :uuid_type

  scope :uploaded_by, ->(user_or_id) { where(uploader_id: user_or_id) }

  sig { params(actor: T.untyped, repository: T.nilable(Repository), key: T.untyped).returns(Storage::Policy) }
  def storage_policy(actor: nil, repository: nil, key: nil)
    ::Storage::MemoryAlphaWithDirectAbsDownloadPolicy.new(self, actor: actor)
  end

  sig { params(policy: Storage::Policy).returns(String) }
  def storage_s3_key(policy)
    "#{uploader_id}/#{guid}"
  end

  sig { override.params(policy: Storage::Policy).returns(String) }
  def storage_abs_key(policy)
    self.storage_s3_key(policy)
  end

  sig { returns(String) }
  def permalink
    UrlHelpers.github_models_attachment_path(guid)
  end

  sig { returns(String) }
  def storage_external_url
    permalink
  end

  sig { returns(String) }
  def storage_s3_bucket
    GitHub.models_attachment_azure_storage_bucket
  end

  sig { returns(String) }
  def storage_s3_access_key
    T.must(GitHub.models_attachment_azure_storage_account)
  end

  sig { returns(String) }
  def storage_s3_secret_key
    T.must(GitHub.models_attachment_azure_storage_secret_key)
  end

  sig { returns T.nilable(::User) }
  def target_for_conditional_access
    uploader
  end

  sig { returns Promise[T.nilable(::User)] }
  def async_target_for_conditional_access
    async_uploader
  end

  sig { returns(T::Boolean) }
  def storage_blob_accessible?
    uploaded?
  end
end
