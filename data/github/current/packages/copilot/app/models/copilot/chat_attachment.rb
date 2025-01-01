# typed: true
# frozen_string_literal: true

class Copilot::ChatAttachment < ApplicationRecord::Domain::Copilot
  include GitHub::Validations
  include Storage::Uploadable
  include Copilot::AzureBlobStorageChatAttachmentDependency
  include Instrumentation::Model

  self.table_name = "copilot_chat_attachments"

  SIZE_LIMIT_IN_MEGABYTES = 20
  CHAT_SPECIFIC_CONTENT_TYPES = {
    "image/webp" => ".webp",
  }

  set_content_types IMAGE_CONTENT_TYPES.merge(CHAT_SPECIFIC_CONTENT_TYPES)
  set_uploadable_policy_path "copilot-chat-attachments"
  add_uploadable_policy_attributes :thread_id

  belongs_to :uploader, class_name: "::User", foreign_key: :uploader_id # rubocop:todo Rails/InverseOf

  # This association must be declared before `before_destroy :storage_delete_object`
  # to ensure its `dependent: :restrict_with_exception` rule is applied first.
  #
  # This is a has_many because a space can be duplicated, and the attachment will be associated with multiple spaces.
  has_many :copilot_space_resources,
    class_name: "::CopilotSpaceResource",
    foreign_key: "copilot_chat_attachment_id",
    inverse_of: :copilot_chat_attachment,
    dependent: :restrict_with_exception

  before_validation :infer_content_type
  before_validation :set_guid, on: :create

  # Check if the content type is allowed, unless it's a text type.
  validates_inclusion_of :content_type, in: allowed_content_types, unless: ->(a) { a.content_type&.start_with? "text/" }
  validate :extension_matches_content_type, unless: ->(a) { a.content_type&.start_with? "text/" }

  validate :validate_file_size
  validates_presence_of :uploader, on: :create
  validates_presence_of :name
  validates :name, unicode3: true
  validate :storage_ensure_inner_asset

  before_destroy :storage_delete_object

  after_commit :instrument_uploaded, if: :saved_change_to_state?

  enum :state, Storage::Uploadable::STATES

  scope :uploaded_by, ->(user_or_id) { where(uploader_id: user_or_id) }

  sig { params(actor: T.untyped, repository: T.nilable(Repository), key: T.untyped).returns(Storage::Policy) } # rubocop:todo Sorbet/ForbidTUntyped
  def storage_policy(actor: nil, repository: nil, key: nil)
    if Rails.env.development?
      ::Storage::MemoryAlphaPolicy.new(self, actor: actor)
    else
      ::Storage::MemoryAlphaWithDirectAbsDownloadPolicy.new(self, actor: actor)
    end
  end

  sig { returns(String) }
  def permalink
    UrlHelpers.copilot_chat_attachment_url(guid, host: GitHub.url)
  end

  sig { returns(String) }
  def storage_external_url
    permalink
  end

  sig { params(actor: T.untyped, expiration: T.nilable(ActiveSupport::Duration)).returns(String) } # rubocop:todo Sorbet/ForbidTUntyped
  def redirect_url(actor: nil, expiration: nil)
    storage_policy(actor: actor).download_url(expiration: expiration)
  end

  def storage_policy_api_url
    "/copilot_internal/chat_attachments/%d" % [id]
  end

  sig { returns(String) }
  def storage_s3_access_key
    T.must(GitHub.copilot_chat_attachment_azure_storage_account)
  end

  sig { returns(String) }
  def storage_s3_secret_key
    T.must(GitHub.copilot_chat_attachment_azure_storage_access_key)
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
  def storage_s3_bucket
    GitHub.copilot_chat_attachment_azure_storage_bucket
  end

  def storage_download_expiration
    5.minutes
  end

  sig { returns T.nilable(User) }
  def target_for_conditional_access
    uploader
  end

  sig { returns Promise[T.nilable(User)] }
  def async_target_for_conditional_access
    async_uploader
  end

  sig { returns(T::Boolean) }
  def storage_blob_accessible?
    uploaded?
  end

  def upload_access_grant(actor)
    Api::AccessControl.access_grant(
      verb: :write_copilot_chat_attachments,
      user: actor,
      owner: uploader
    )
  end

  def self.primary_and_secondary_abs_urls
    ::Storage::AzureSign.primary_and_secondary_abs_urls(Copilot::AzureBlobStorageChatAttachmentDependency.abs_storage_account_name)
  end

  def instrument_uploaded
    return true unless uploaded?

    # Do not scan if a Copilot for Business or Copilot Enterprise user uploaded the attachment
    copilot_user = Copilot::Public::User::new(T.must(uploader))

    return true if copilot_user.has_enterprise_seat?

    GlobalInstrumenter.instrument "copilot.chat_attachment.scan_requested", {
      attachment: self,
      upload_ip: GitHub.context[:actor_ip],
    }
  end

  def platform_type_name
    "CopilotChatAttachment"
  end

  def storage_azure_content_disposition
    "attachment; filename=\"#{name}\""
  end

  def storage_download_content_type
    content_type || "application/octet-stream"
  end

  def storage_s3_download_query(query)
    query[:"response-content-disposition"] = storage_azure_content_disposition
    query[:"response-content-type"] = storage_download_content_type
  end

  def validate_file_size
    return unless size

    unless size.in?(1..SIZE_LIMIT_IN_MEGABYTES.megabytes)
      errors.add(:base, "File \"#{name}\" is too large. The maximum size for this file type is #{SIZE_LIMIT_IN_MEGABYTES}MB.")
    end
  end
end
