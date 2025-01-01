# typed: true
# frozen_string_literal: true

class Copilot::ChatAttachment < ApplicationRecord::Domain::Copilot
  include GitHub::Validations
  include Storage::Uploadable
  include Copilot::AzureBlobStorageChatAttachmentDependency
  include Instrumentation::Model

  self.table_name = "copilot_chat_attachments"

  SIZE_LIMIT_IN_MEGABYTES = 20

  set_content_types :images
  set_uploadable_policy_path "copilot-chat-attachments"

  belongs_to :uploader, class_name: "::User", foreign_key: :uploader_id # rubocop:todo Rails/InverseOf

  before_validation :set_guid, on: :create

  validates_inclusion_of :content_type, in: allowed_content_types
  validate :extension_matches_content_type
  validates_inclusion_of :size, in: 1..SIZE_LIMIT_IN_MEGABYTES.megabytes,
    message: "File is too big. Try again with a file size less than #{SIZE_LIMIT_IN_MEGABYTES}MB."
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
    ::Storage::MemoryAlphaWithDirectAbsDownloadPolicy.new(self, actor: actor)
  end

  sig { returns(String) }
  def permalink
    UrlHelpers.copilot_chat_attachment_url(id, host: GitHub.url)
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

  def memory_alpha_fastly_acceleration_bucket(actor, repository)
    nil
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
end
