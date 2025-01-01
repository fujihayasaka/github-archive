# typed: true
# frozen_string_literal: true

class RepositoryImage < ApplicationRecord::Domain::AssetObjects
  include GitHub::Relay::GlobalIdentification
  include ::Storage::Uploadable
  include Instrumentation::Model # must come after ::Storage::Uploadable is included


  # Necessary to upload images. See UploadPoliciesController#create.
  set_uploadable_policy_path "repository-images"
  add_uploadable_policy_attributes :repository_id
  set_content_types :images

  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain legacy_return_type: true
  belongs_to :storage_blob, class_name: "Storage::Blob"
  belongs_to :uploader, class_name: "User", foreign_key: :uploader_id # rubocop:todo Rails/InverseOf

  validates :repository, :uploader, :size, presence: true
  validates :repository_id, uniqueness: { scope: :guid }
  validate :storage_ensure_inner_asset
  validate :uploader_access, on: :create
  validates_inclusion_of :content_type, in: allowed_content_types
  validates_presence_of :name
  validate :extension_matches_content_type
  validates_inclusion_of :size, in: 1..1.megabyte

  before_validation :set_guid, on: :create
  before_destroy :storage_delete_object_and_purge_cdn # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_create :delete_old_open_graph_images_for_repo # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  attr_accessor :destroyer
  after_create_commit :instrument_create # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_destroy_commit :instrument_destroy # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  enum :role, { open_graph: 0 }

  enum :state, Storage::Uploadable::STATES

  scope :open_graph, -> { where(role: roles[:open_graph]) }

  # BEGIN storage settings
  def self.storage_s3_bucket
    "github-#{Rails.env.downcase}-repository-image-32fea6"
  end

  def target_for_conditional_access
    repository&.target_for_conditional_access
  end

  def async_target_for_conditional_access
    async_repository.then { |x| T.must(x).async_target_for_conditional_access }
  end

  def storage_policy(actor: nil, repository: nil, key: nil)
    klass = if GitHub.storage_cluster_enabled?
      ::Storage::ClusterPolicy
    else
      ::Storage::S3Policy
    end
    klass.new(self, actor: actor, repository: self.repository)
  end

  def self.storage_new(uploader, blob, meta)
    new(
      storage_blob: blob,
      uploader: uploader,
      content_type: meta[:content_type],
      name: meta[:name],
      size: meta[:size],
      repository_id: meta[:repository_id],
    )
  end

  def self.storage_create(uploader, blob, meta)
    storage_new(uploader, blob, meta).tap do |image|
      image.update(state: :uploaded)
    end
  end

  def upload_access_grant(actor)
    Api::AccessControl.access_grant(verb: :edit_repo, resource: repository, user: actor)
  end

  def storage_external_url(actor = nil)
    if cdn_url = GitHub.repository_images_cdn_url
      cdn_url + storage_s3_key(policy = nil)
    elsif GitHub.storage_cluster_enabled?
      root_url = GitHub.storage_private_mode_url || GitHub.storage_cluster_url
      "#{root_url}/repository/#{repository_id}/images/#{guid}"
    else
      "#{GitHub.asset_url_host}#{storage_s3_key(storage_policy(actor: actor))}"
    end
  end

  def creation_url
    "#{GitHub.storage_cluster_url}/repository/#{repository_id}/images"
  end

  def storage_blob_accessible?
    uploaded?
  end

  def storage_upload_path_info(policy)
    "/internal/storage/repository/#{repository_id}/images"
  end

  def storage_cluster_download_token(policy)
    super unless !GitHub.private_mode_enabled? && repository&.public?
  end

  def storage_download_path_info(policy)
    "#{storage_upload_path_info(policy)}/#{guid}"
  end

  def storage_uploadable_attributes
    { repository_id: repository_id }
  end

  # cluster settings

  def storage_cluster_url(policy)
    "#{GitHub.storage_cluster_url}/repository-images/#{repository_id}/files/#{guid}"
  end

  # s3 storage settings

  def storage_s3_bucket
    self.class.storage_s3_bucket
  end

  def storage_s3_key(policy)
    "#{repository_id}/#{guid}"
  end

  def storage_s3_access_key
    GitHub.s3_production_data_access_key
  end

  def storage_s3_secret_key
    GitHub.s3_production_data_secret_key
  end

  def storage_s3_access
    :public
  end

  def storage_s3_upload_header
    {
      "Content-Type" => content_type,
      "Cache-Control" => "max-age=2592000",
      "x-amz-meta-Surrogate-Control" => "max-age=31557600",
    }
  end

  # END storage settings

  # Audit log event prefix.
  def event_prefix
    :repository_image
  end

  # Public: Returns true if the given User can delete this image.
  def deletable_by?(actor)
    repository&.async_can_set_social_preview?(actor, allow_site_admin: true).sync
  end

  # Audit log event payload.
  def event_payload
    payload = {
      :repo => repository,
      :content_type => content_type,
      :size => size,
      :role => role,
      event_prefix => self,
    }
    payload[repository&.owner&.event_prefix] = repository&.owner if repository&.owner
    payload
  end

  def event_context(prefix: event_prefix)
    {
      "#{prefix}_id".to_sym => id,
      prefix => name,
    }
  end

  private

  def storage_delete_object_and_purge_cdn
    storage_delete_object

    if GitHub.repository_images_cdn_url
      PurgeFastlyUrlJob.perform_later({ "url" => storage_external_url })
    end
  end

  def uploader_access
    return unless repository

    unless repository&.async_can_set_social_preview?(uploader).sync
      user_desc = uploader ? uploader : "anonymous user"
      errors.add :uploader,
        "#{user_desc} does not have access to upload an image for the specified repository"
    end
  end

  def delete_old_open_graph_images_for_repo
    return unless open_graph?

    T.must(repository).repository_images.open_graph.where.not(id: id).destroy_all
  end

  def instrument_create
    instrument :create, actor: uploader

    hydro_payload = {
      uploader: uploader,
      repository_image: self,
      repository: repository,
    }
    GlobalInstrumenter.instrument("repository_image.created", hydro_payload)
  end

  def instrument_destroy
    instrument :destroy, actor: destroyer

    hydro_payload = {
      actor: destroyer,
      repository_image: self,
    }
    GlobalInstrumenter.instrument("repository_image.deleted", hydro_payload)
  end
end
