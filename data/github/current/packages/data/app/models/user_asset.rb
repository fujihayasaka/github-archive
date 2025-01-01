# typed: false
# frozen_string_literal: true

# Tracks files uploaded and stored by users. This is used by the drag-and-drop
# image uploader on conversation forms.
class UserAsset < ApplicationRecord::Domain::AssetObjects
  include ::Storage::Uploadable
  include Instrumentation::Model
  include UserAsset::Quarantine
  include LegacyImportable

  set_uploadable_policy_path :assets
  add_uploadable_policy_attributes :repository_id, :upload_container_type, :upload_container_id

  set_content_types :media

  belongs_to :storage_blob, class_name: "Storage::Blob"
  belongs_to :repository
  belongs_to :uploader, class_name: "User", foreign_key: :user_id # rubocop:todo Rails/InverseOf
  belongs_to :upload_container, polymorphic: true
  has_many :attachments, foreign_key: :asset_id, dependent: :delete_all # rubocop:todo Rails/InverseOf

  before_validation :set_guid, on: :create
  validate :storage_ensure_inner_asset
  validates_inclusion_of :content_type,
    in: lambda { |asset| asset.class.allowed_content_types }
  validates_presence_of :name
  validate :extension_matches_content_type

  # Most user assets and videos are restricted to this size limit.
  ASSET_SIZE_LIMIT = 10.megabytes

  # Video assets can be up to this size, when on a paid plan.
  # See UploadPoliciesController for how that is determined and enforced.
  VIDEO_PAID_SIZE_LIMIT = 100.megabytes

  # Regex to match canonical URLs for assets
  # matches https://github.com/Auth-Rewrite/test-stafftools-delete/assets/839181/8d7ffbbb-dc3d-4c7b-a0d8-7a655b818b47
  # matches: user_id, guid i.e 839181, 8d7ffbbb-dc3d-4c7b-a0d8-7a655b818b47
  CANONICAL_URL_REGEX = %r{\A#{GitHub.url}(?::\d+)?\/[\w.-]+\/[\w.-]+\/assets\/(\d+)\/([^\.]+)}

  # Date in which the private images feature flag was enabled.
  PRIVATE_IMAGES_FEATURE_FLAG_TIMESTAMP = "2023-05-09T10:03:00.000Z"

  REPOSITORY_BLOB = "RepositoryBlob"

  validates_inclusion_of :size, in: 1..ASSET_SIZE_LIMIT, unless: :video_content?,
    message: "Yowza that's a big file. <span class='drag-and-drop-error-info'> <span class='btn-link'>Try again</span> with a file size less than 10MB.</span>"
  validates_inclusion_of :size, in: 1..VIDEO_PAID_SIZE_LIMIT, if: :video_content?,
    message: "Yowza that's a big file. <span class='drag-and-drop-error-info'> <span class='btn-link'>Try again</span> with a file size less than 100MB.</span>"

  validates_presence_of :uploader, on: :create
  validate :repository_and_upload_container_access, on: :create
  before_create :choose_storage_provider
  before_create :set_url_flag #rubocop:todo GitHub/AvoidActiveRecordCallbacks
  before_destroy :storage_delete_objects

  after_commit :instrument_uploaded, if: :saved_change_to_state?

  enum :state, Storage::Uploadable::STATES

  default_scope { where(quarantining: nil) }

  scope :quarantined, -> { unscoped.where(quarantining: true) }

  # Public: Filter user assets to a subset of the given list by removing those assets that
  # have been determined to be illegal or of extreme violence.
  # See github.com/github/schaefer for more
  scope :subset_without_known_photo_dna_hits, ->(user_assets) do
    ids_of_known_hits = PhotoDnaHit.for_user_asset(user_assets).pluck(:content_id)
    where(id: user_assets).where.not(id: ids_of_known_hits)
  end

  def self.multiple_target_for_conditional_access(assets)
    ConditionalAccess::Filter.ensure_with_class(assets, UserAsset)
    id_to_uploader = User.where(id: assets.pluck(:user_id)).index_by(&:id)
    assets.each_with_object({}) do |asset, result|
      result[asset] = id_to_uploader[asset.user_id] || :no_target_for_conditional_access
    end
  end

  def target_for_conditional_access
    uploader&.target_for_conditional_access || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def async_target_for_conditional_access
    async_uploader.then do |uploader|
      uploader&.async_target_for_conditional_access || :no_target_for_conditional_access
    end
  end

  def instrument_uploaded
    return true unless uploaded?

    # If the respective feature flags are on, publish a UserAssetScan hydro event to scan
    # images/videos for explicit content.
    if (image_content? && GitHub.flipper[:schaefer_instrument_upload].enabled?(uploader)) ||
        (video_content? && GitHub.flipper[:schaefer_instrument_video_upload].enabled?(uploader))
      GlobalInstrumenter.instrument "user_asset.uploaded", {
        user_asset: self,
        upload_ip: GitHub.context[:actor_ip],
      }
    end

    # Always publish a UserAssetCreate hydro event.
    GlobalInstrumenter.instrument "user_asset.create", { user_asset: self }
  end

  def upload_container
    if uploader&.feature_enabled?(:secured_advisory_uploads)
      # Edge case: if the upload container type is a RepositoryAdvisory, we need to calculate the upload container
      # before attempting to fallback to the repository, since `repository_id` will be non-nil.
      return super if upload_container_type == RepositoryAdvisory.name
    end

    if upload_container_type == REPOSITORY_BLOB || repository_id
      Repository.find_by_id(repository_id)
    else
      super
    end
  end

  # BEGIN storage settings

  # Purge this asset from the CDN after it's deleted from the database.
  # We need PurgeFastlyUrlJob to be able to delete using the right CDN url (i.e for private/public assets)
  def purge
    return destroy if GitHub.storage_cluster_enabled? || GitHub.multi_tenant_enterprise?

    # storage_external_url may return the canonical url for the asset (i.e for private/public assets on dotcom)
    # example: https://github.com/(owner)/(repo)/assets/(1234)/(guid)
    urls = [storage_external_url]
    with_storage_provider(:default) do
      urls << storage_external_url
    end

    destroy

    urls.compact.each do |url|
      # If the URL is a canonical URL, we need to purge both the public and private URLs
      # by generating the right URLs.
      # example canonical url: https://github.com/Auth-Rewrite/test-stafftools-delete/assets/839181/8d7ffbbb-dc3d-4c7b-a0d8-7a655b818b47
      if CANONICAL_URL_REGEX.match?(url)
        user_id, guid = CANONICAL_URL_REGEX.match(url).captures

        extension = File.extname(name)
        # generated_urls should be of the form: https://cdn_url/<user_id>/<asset-id>-<guid>.<extension>
        # public_cdn_url: https://user-images.githubusercontent.com/839181/245163276-0e964155-5d21-4c7b-a299-b6f6a69d30ac.png
        # private_cdn_url: https://private-user-images.githubusercontent.com/1226121/245160441-45ef83b0-4bd7-4459-8433-6a364adbeda5.png?<jwt>
        public_url = "#{GitHub.user_images_cdn_url}#{user_id}/#{id}-#{guid}#{extension}"
        private_url = "#{GitHub.private_user_images_cdn_url}/#{user_id}/#{id}-#{guid}#{extension}"

        # This is a hack to purge the CDN assets for both private and public assets, since
        # we don't store private/public information in the database.
        PurgeFastlyUrlJob.perform_later({ "url" => public_url })
        PurgeFastlyUrlJob.perform_later({ "url" => private_url })
      else
        PurgeFastlyUrlJob.perform_later({ "url" => url })
      end

    end
  end

  def storage_policy(actor: nil, repository: nil, key: nil)
    klass = if GitHub.storage_cluster_enabled?
      ::Storage::ClusterPolicy
    elsif GitHub.multi_tenant_enterprise?
      ::Storage::MemoryAlphaPolicy
    else
      ::Storage::S3Policy
    end
    klass.new(self, actor: actor, repository: repository)
  end

  # deletes from old and new aws accounts
  def storage_delete_objects
    if storage_provider == :s3_production_data
      with_storage_provider(:default) do
        storage_delete_object
      end
    end
    storage_delete_object
  end

  # Temporarily changes the storage provider to build URLs for the old S3
  # account. Necessary hack to purge cloud.githubusercontent.com until it
  # proxies from the new S3 account exclusively. Not needed in GHE.
  def with_storage_provider(prov)
    orig = read_attribute(:storage_provider)
    self.storage_provider = prov == :default ? nil : prov.to_s
    yield
  ensure
    self.storage_provider = orig
  end

  def self.storage_new(uploader, blob, meta)
    new(
      storage_blob: blob,
      uploader: uploader,
      content_type: meta[:content_type],
      name: meta[:name],
      repository_id: meta[:repository_id],
      upload_container_type: meta[:upload_container_type],
      upload_container_id: meta[:upload_container_id],
    )
  end

  def self.storage_create(uploader, blob, meta)
    storage_new(uploader, blob, meta).tap do |file|
      file.update(state: :uploaded)
    end
  end

  def source_url(actor:)
    if secured_asset? && !private_authed_image?
      redirect_url(actor: actor)
    else
      storage_external_url
    end
  end

  def redirect_url(actor: nil, secure_user_assets: false, expiration: nil)
    url = storage_policy(actor: actor, repository: repository).download_url(expiration: expiration)
    if secured_asset?
      # GitHub.com + CDN + secured
      url.gsub("https://#{storage_s3_bucket}.s3.amazonaws.com/", GitHub.secured_user_images_cdn_url)
    elsif !GitHub.storage_cluster_enabled? && secure_user_assets
      # GitHub.com + CDN
      url.gsub("https://#{storage_s3_bucket}.s3.amazonaws.com/", GitHub.user_images_cdn_url)
    else
      url
    end
  end

  # Check if a user has access to a specific asset
  # by default unless there is a container that specifically
  # supports for access control we return true.
  def has_access?(actor)
    return true unless private_authed_image? || private_upload_container_asset?

    if uploader&.feature_enabled?(:secured_advisory_uploads)
      if upload_container
        case upload_container
        when MemexProject
          return upload_container.viewer_can_read?(actor)
        when RepositoryAdvisory
          return upload_container.readable_by?(actor)
        when User
          # We are showing private assets in saved reply to everyone in  in Proxima until we implement copy operation
          return upload_container == actor
        when Repository
          return upload_container.readable_by?(actor)
        when Gist
          # Gists are made private by concealing their URLs. Anyone who has the URL can view the gist, irrespective of
          # whether they are logged in or not.
          return true
        else
          # Other containers will need to implement their own interfaces, if they
          # do not we just consider the asset not reachable for avoiding leaking
          # private assets.
          return false
        end
      elsif upload_container_type
        # Handle cases where assets can be created before their accompanying container.
        case upload_container_type
        when RepositoryAdvisory.name
          return !actor.nil? && actor.respond_to?(:id) && user_id == actor.id
        when Gist.name
          # Gists are made private by concealing their URLs. Anyone who has the URL can view the gist, irrespective of
          # whether they are logged in or not.
          return true
        else
          # Other containers will need to implement their own interfaces, if they
          # do not we just consider the asset not reachable for avoiding leaking
          # private assets.
          return false
        end
      end
    else
      if repository
        return repository.readable_by?(actor)
      elsif upload_container
        case upload_container
        when MemexProject
          return upload_container.viewer_can_read?(actor)
        when User
          # We are showing private assets in saved reply to everyone in  in Proxima until we implement copy operation
          return upload_container == actor
        else
          # Other containers will need to implement their own interfaces, if they
          # do not we just consider the asset not reachable for avoiding leaking
          # private assets.
          return false
        end
      end
    end

    return true unless GitHub.multi_tenant_enterprise?

    # We should never reach that code path, multi tenant enterprise should
    # always populate the repository_id or upload_container_id, but just in case
    # we do not want to leak private assets.
    false
  end

  def secured_asset?
    return @secured_asset if defined?(@secured_asset)

    @secured_asset = !GitHub.storage_cluster_enabled? && legacy_secured_images?
  end

  def private_authed_image?
    return true if GitHub.multi_tenant_enterprise?
    return @private_authed_image if defined?(@private_authed_image)

    @private_authed_image = repository_id && repository.present? &&
      GitHub.flipper[:secure_user_assets_auth_check].enabled?(repository.async_owner.sync)
  end

  def legacy_secured_images?
    return @legacy_secured_images if defined?(@legacy_secured_images)

    @legacy_secured_images = repository_id && repository.present? &&
      GitHub.flipper[:secured_images].enabled?(repository.async_organization.sync)
  end

  def private_upload_container_asset?
    return true if GitHub.multi_tenant_enterprise?
    if uploader&.feature_enabled?(:secured_advisory_uploads)
      # Assets uploaded to a container while it is still being created will not have an upload_container_id, but may
      # still require private access.
      return true if upload_container_id.nil? && upload_container_type.present?
    end
    return false unless upload_container
    return @private_upload_container_asset if defined?(@private_upload_container_asset)

    uc_owner = if upload_container.respond_to?(:async_owner)
      upload_container.async_owner.sync
    elsif upload_container.respond_to?(:owner)
      upload_container.owner
    end

    @private_upload_container_asset = uc_owner && GitHub.flipper[:secure_user_assets_auth_check].enabled?(uc_owner)
  end

  def storage_external_url(_ = nil)
    return determine_storage_external_url(
      storage_cluster_fallback_url,
      is_repository_available: legacy_secured_images? || repository
    ) if GitHub.storage_cluster_enabled?

    return determine_storage_external_url(
      s3_production_data_fallback_url,
      is_repository_available: repository && (private_authed_image? || legacy_secured_images?)
    ) if storage_provider == :s3_production_data

    "#{GitHub.asset_url_host}#{storage_s3_key(policy = nil)}"
  end

  def determine_storage_external_url(fallback_url, is_repository_available: false)
    return "#{GitHub.url}/user-attachments/assets/#{guid}" if using_new_url? && is_repository_available
    return "#{repository.permalink}/assets/#{user_id}/#{guid}" if is_repository_available

    return upload_container_storage_external_url(fallback_url) if !repository && upload_container

    # UserAssets may be uploaded to gists without an upload_container_id. This can occur when the gist has not been
    # created yet.
    return Gist.new.private_asset_url(user_id, guid, using_new_url?) if upload_container_type == Gist.name

    fallback_url
  end

  def upload_container_storage_external_url(fallback_url)
    # Upload containers that need private assets must implement the `private_asset_url` method
    if upload_container.respond_to?(:private_asset_url)
      url = upload_container.private_asset_url(user_id, guid, using_new_url?)
      return url unless url.empty?
    end

    fallback_url
  end

  def storage_cluster_fallback_url
    "#{GitHub.storage_cluster_url}/user/#{user_id}/files/#{guid}"
  end

  def s3_production_data_fallback_url
    return GitHub.user_images_cdn_url + storage_s3_key(policy = nil) if GitHub.user_images_cdn_url
    storage_policy.download_url
  end

  def legacy_storage_external_url
    return if GitHub.enterprise?
    return if created_at > Time.find_zone("UTC").parse(PRIVATE_IMAGES_FEATURE_FLAG_TIMESTAMP)

    GitHub.user_images_cdn_url + storage_s3_key(policy = nil)
  end

  def storage_blob_accessible?
    uploaded?
  end

  def creation_url
    return "#{GitHub.storage_cluster_url}/user/#{user_id}/repository/#{repository_id}/files" if legacy_secured_images?
    "#{GitHub.storage_cluster_url}/user/#{user_id}/files"
  end

  def upload_access_grant(actor)
    Api::AccessControl.access_grant(
      verb: :write_user_files,
      user: actor,
      owner: uploader,
      resource: repository,
    )
  end

  # cluster settings

  def storage_cluster_url(policy)
    creation_url + "/#{guid}"
  end

  def storage_upload_path_info(policy)
    return "/internal/storage/user/#{user_id}/repository/#{repository_id}/files" if repository_id && legacy_secured_images?
    "/internal/storage/user/#{user_id}/files"
  end

  def storage_download_path_info(policy)
    "#{storage_upload_path_info(policy)}/#{guid}"
  end

  # Public: Describes the filters that are run when images are uploaded.
  def alambic_upload_filters
    return {} if video_content? || svg_content?

    {
      original: [
        {
          command: :imagemagick,
          params: {
            max_width: "10000",
            max_height: "10000",
            strip: :exif,
            orient: :auto,
          },
        },
      ],
    }
  end

  def video_content?
    ::Storage::Uploadable::VIDEO_CONTENT_TYPES.keys.include? content_type
  end

  def svg_content?
    ::Storage::Uploadable::SVG_CONTENT_TYPE.keys.include? content_type
  end

  def image_content?
    ::Storage::Uploadable::IMAGE_CONTENT_TYPES.keys.include? content_type
  end

  # s3 storage settings

  def storage_s3_client
    return GitHub.memory_alpha_client(GitHub.uploadable_storage_account,
      GitHub.uploadable_access_key)  if self.storage_policy.is_a? ::Storage::MemoryAlphaPolicy

    if storage_provider == :s3_production_data
      GitHub.s3_production_data_client
    else
      GitHub.s3_primary_client
    end
  end

  def storage_s3_bucket
    if storage_provider == :s3_production_data
      self.class.storage_s3_new_bucket
    else
      self.class.storage_s3_bucket
    end
  end

  def storage_fastly_acceleration_bucket(repository)
    self.class.storage_fastly_acceleration_bucket
  end

  def storage_s3_key(policy)
    if storage_provider == :s3_production_data
      "#{user_id}/#{id}-#{guid}#{File.extname(name)}"
    else
      "#{GitHub.asset_base_path}/#{user_id}/#{id}/#{guid}#{File.extname(name)}"
    end
  end

  def storage_s3_access_key
    if GitHub.multi_tenant_enterprise?
      GitHub.uploadable_storage_account
    elsif storage_provider == :s3_production_data
      GitHub.s3_production_data_access_key
    else
      GitHub.s3_environment_config[:access_key_id]
    end
  end

  def storage_s3_secret_key
    if GitHub.multi_tenant_enterprise?
      GitHub.uploadable_access_key
    elsif storage_provider == :s3_production_data
      GitHub.s3_production_data_secret_key
    else
      GitHub.s3_environment_config[:secret_access_key]
    end
  end

  def storage_s3_access
    :private
  end

  def storage_s3_upload_header
    {
      "Content-Type" => content_type,
      "Cache-Control" => "max-age=2592000",
      "x-amz-meta-Surrogate-Control" => "max-age=31557600",
    }
  end

  def storage_transition_ready?
    uploader && storage_blob_accessible?
  end

  # END storage settings

  def storage_policy_api_url
    "/assets/#{guid}"
  end

  # Needed for test/lib/github/transitions/20151211173128_enterprise_storage_cluster_upgrade_test.rb
  def alambic_absolute_local_path
    parts = [GitHub.file_asset_path, GitHub.asset_base_path]
    parts.push *("%08d" % user_id).scan(/..../)
    parts.push *("%08d" % id).scan(/..../)
    parts << (guid + asset_extension)
    parts * "/"
  end

  # Turn AssetScanner::Match objects into Assets to attach them to comments.
  # If the Asset ID is missing, load the Asset from its guid.
  #
  # matches - Array of AssetScanner::Match objects.
  #
  # Returns an Array of Asset objects.
  def self.from_matches(matches)
    asset_ids = []
    guids = []
    asset_id_guids = {} # int ID => string guid
    matches.each do |match|
      if id_string = match.asset_id
        id = id_string.to_i
        next unless id > 0
        asset_id_guids[id] = match.asset_guid
        asset_ids << id
      elsif guid = match.asset_guid
        next if guid.blank?
        guids << guid
      end
    end

    assets = []

    ActiveRecord::Base.connected_to(role: :reading) do
      asset_ids.each_slice(100) do |slice|
        found = UserAsset.where(id: slice).all.select do |user_asset|
          expected_guid = asset_id_guids[user_asset.id]
          # expected_guid is matched in the regex run on the img url
          # if the asset ID and guid are BOTH matched, then require the returned
          # UserAsset to have the same guid.
          expected_guid.blank? || user_asset.guid == expected_guid
        end
        assets.push(*found) if found.present?
      end

      guids.each_slice(100) do |slice|
        found = UserAsset.where(guid: slice).all
        assets.push(*found) if found.present?
      end
    end

    assets.uniq!
    assets
  end

  def self.storage_s3_bucket
    GitHub.s3_environment_config[:asset_bucket_name]
  end

  def self.storage_s3_new_bucket
    GitHub.s3_user_asset_new_bucket
  end

  def self.storage_s3_new_bucket_host
    GitHub.s3_user_asset_new_host
  end

  def self.storage_fastly_acceleration_bucket
    # Not configured
  end

  def choose_storage_provider
    return if GitHub.storage_cluster_enabled?
    self.storage_provider = :s3_production_data
  end

  def set_url_flag
    if GitHub.flipper[:new_user_asset_url].enabled?(self.uploader)
      self.using_new_url = true
    end
  end

  def event_prefix() :assets end

  def self.instrument_user_assets_batch_scan(payload)
    GitHub.instrument "user_asset.batch_scan", payload
  end

  def self.instrument_repository_assets_batch_scan(payload)
    GitHub.instrument "repository_asset.batch_scan", payload
  end

  def under_paid_video_size_limit_and_paying?(is_paid_plan)
    is_paid_plan && size <= UserAsset::VIDEO_PAID_SIZE_LIMIT
  end

  def over_base_limit_on_free_plan?(is_paid_plan)
    !is_paid_plan && size > UserAsset::ASSET_SIZE_LIMIT
  end

  def over_paid_limit_on_paid_plan?(is_paid_plan)
    is_paid_plan && size > UserAsset::VIDEO_PAID_SIZE_LIMIT
  end

  def under_base_asset_size_limit?
    size < UserAsset::ASSET_SIZE_LIMIT
  end

  def create_s3_copy(new_container_type, new_container_id)
    raise NotImplementedError if GitHub.enterprise?
    copy = self.dup
    copy.guid = nil
    copy.upload_container_type = new_container_type
    copy.upload_container_id = new_container_id
    copy.repository_id = new_container_id if copy.upload_container_type == Repository.name
    copy.save!
    begin
      response = self.storage_s3_client.copy_object(
        acl: copy.storage_policy.acl,
        bucket: copy.storage_s3_bucket,
        copy_source: "#{self.storage_s3_bucket}/#{self.storage_s3_key(self.storage_policy)}",
        key: copy.storage_s3_key(copy.storage_policy),
      )
      copy
    rescue Storage::UserAssetTransfer::Copy::CopyTimeoutError => e
      raise e # TimeoutError is handled in the caller
    rescue StandardError => e
      copy.purge # This is the best effort we can do to clean up the copy. It is not guaranteed to work.
      raise e
    end
  end

  private

  def repository_and_upload_container_access
    return validate_access_to_model(Repository.name) { |repo| repo.pullable_by?(uploader) } if repository_id
    validate_upload_container_access
  end

  def validate_upload_container_access
    access_checks = {
      MemexProject.name => ->(project) { project.viewer_can_read?(uploader) },
      User.name => ->(user) { user == uploader },
      REPOSITORY_BLOB => ->(repo) { repo.pullable_by?(uploader) }
    }

    access_check = access_checks[upload_container_type]
    validate_access_to_model(upload_container_type, &access_check) if access_check
  end

  def validate_access_to_model(model_name, &block)
    model_data = if model_name == Repository.name
      { id: repository_id, error_field: :repository_id }
    else
      { id: upload_container_id, error_field: :upload_container_id }
    end

    model_name = Repository.name if model_name == REPOSITORY_BLOB

    begin
      the_model = model_name.constantize
    rescue NameError
      return errors.add :upload_container_type, "invalid container type #{model_name}"
    end

    model_instance = the_model.find_by_id(model_data[:id])
    return errors.add model_data[:error_field], "is not a valid #{model_name}" unless model_instance

    return if importing?

    errors.add :uploader_id, "does not have read access to the specified #{model_name}" unless yield(model_instance)
  end
end
