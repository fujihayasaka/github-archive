# typed: true
# frozen_string_literal: true

# Tracks Oauth Application logos uploaded by users.
class OauthApplicationLogo < ApplicationRecord::Domain::Integrations
  include ::Storage::Uploadable
  include GitHub::Validations

  set_uploadable_policy_path :oauth_applications
  add_uploadable_policy_attributes :application_id

  set_content_types :images

  has_one :oauth_application, foreign_key: :logo_id # rubocop:todo Rails/InverseOf
  belongs_to :application, class_name: "OauthApplication", foreign_key: :application_id # rubocop:todo Rails/InverseOf
  belongs_to :storage_blob, class_name: "Storage::Blob"
  belongs_to :uploader, class_name: "User", foreign_key: :uploader_id # rubocop:todo Rails/InverseOf

  before_validation :set_guid, on: :create
  validate :storage_ensure_inner_asset
  validates_presence_of :uploader_id
  validate :uploader_access, on: :create
  validates_inclusion_of :content_type, in: allowed_content_types
  validates_presence_of :name
  validates :name, unicode3: true
  validate :extension_matches_content_type
  validates_inclusion_of :size, in: 1..5.megabytes

  before_destroy :storage_delete_object

  after_save :associate_to_application

  enum :state, Storage::Uploadable::STATES

  # BEGIN storage settings

  def storage_policy(actor: nil, repository: nil, key: nil)
    klass = if GitHub.storage_cluster_enabled?
      ::Storage::ClusterPolicy
    else
      ::Storage::S3Policy
    end
    klass.new(self, actor: actor, repository: repository)
  end

  def self.storage_new(uploader, blob, meta)
    new(
      storage_blob: blob,
      uploader: uploader,
      content_type: meta[:content_type],
      name: meta[:name],
      size: meta[:size],
      application_id: meta[:application_id],
    )
  end

  def self.storage_create(uploader, blob, meta)
    storage_new(uploader, blob, meta).tap do |logo|
      logo.update(state: :uploaded)
    end
  end

  def target_for_conditional_access
    T.must(oauth_application).target_for_conditional_access
  end

  def async_target_for_conditional_access
    async_oauth_application.then(&:async_target_for_conditional_access)
  end

  def starter?
    super || state.blank?
  end

  def storage_blob_accessible?
    uploaded?
  end

  def storage_external_url(_ = nil)
    if GitHub.storage_cluster_enabled?
      root_url = GitHub.storage_private_mode_url || GitHub.storage_cluster_url
      "#{root_url}/oauth_logos/#{guid}"
    else
      "#{GitHub.asset_url_host}#{storage_s3_key(storage_policy)}"
    end
  end

  def creation_url
    "#{GitHub.storage_cluster_url}/oauth_logos"
  end

  # cluster settings

  def storage_cluster_url(policy)
    "#{creation_url}/#{guid}"
  end

  def storage_cluster_download_token(policy)
    # no token needed for downloads
  end

  def storage_upload_path_info(policy)
    "/internal/storage/oauth_logos"
  end

  def storage_uploadable_attributes
    {
      application_id: application_id,
    }
  end

  def upload_access_grant(actor)
    Api::AccessControl.access_grant(
      verb: :public_site_information,
    )
  end

  # Public: Describes the filters that are run when images are uploaded.
  def alambic_upload_filters
    {
      original: [
        {
          command: :imagemagick,
          params: {
            max_width: "10000",
            max_height: "10000",
            resize: "800x800>",
            strip: :exif,
            orient: :auto,
            flatten: :animations,
          },
        },
      ],
    }
  end

  # s3 storage settings

  def storage_s3_key(policy)
    "#{GitHub.asset_base_path}/#{uploader_id}/#{id}/#{guid}#{File.extname(name)}"
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

  def alambic_s3_meta
    @alambic_s3_meta ||= {
      # how long browsers cache the asset from fastly
      "Cache-Control" => "max-age=31557600",
      # how long fastly caches the asset from s3
      "x-amz-meta-Surrogate-Control" => "max-age=31557600",
      "x-amz-meta-Surrogate-Key" => "user-#{uploader_id}" }
  end

  # Needed for test/lib/github/transitions/20151211173128_enterprise_storage_cluster_upgrade_test.rb
  def alambic_absolute_local_path
    parts = [GitHub.file_asset_path, GitHub.asset_base_path]
    parts.push *("%08d" % uploader_id).scan(/..../)
    parts.push *("%08d" % id).scan(/..../)
    parts << "#{guid}#{asset_extension}"
    parts * "/"
  end

  def uploaded=(value)
    self.state = value ? :uploaded : :starter
    write_attribute :uploaded, value
  end

  def self.storage_s3_bucket
    GitHub.s3_environment_config[:asset_bucket_name]
  end

  include Instrumentation::Model
  def event_prefix() :oauth_application_assets end

  private

  def associate_to_application
    return if application_id.nil?
    return unless saved_change_to_application_id?
    T.must(application).update(logo_id: id)
  end

  def uploader_access
    return if application.nil?
    return if T.must(application).avatar_editable_by?(uploader)
    errors.add :uploader_id, "does not have access to edit application #{application_id}"
  end
end
