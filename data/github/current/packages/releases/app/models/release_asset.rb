# typed: true
# frozen_string_literal: true

class ReleaseAsset < ApplicationRecord::Domain::AssetObjects # rubocop:todo GitHub/DatabaseModelsShouldHaveTests
  extend Releases::IReleaseAsset

  include GitHub::Validations
  include GitHub::Relay::GlobalIdentification
  include ::Storage::Uploadable
  include SlottedCounterService::Countable
  include Releases::IReleaseAsset

  set_uploadable_policy_path :releases
  add_uploadable_policy_attributes :repository_id, :release_id, :label, :deletion_candidates

  belongs_to :repository
  belongs_to :release
  belongs_to :uploader, class_name: "User", foreign_key: :uploader_id # rubocop:todo Rails/InverseOf
  belongs_to :storage_blob, class_name: "Storage::Blob"

  before_validation :denormalize_release, on: :create
  validates_presence_of :repository_id, :release_id
  validate :storage_ensure_inner_asset
  validate :uploader_access, on: :create
  validate :extension_is_allowed
  validate :content_type_is_allowed
  validate :name_is_unique
  validates :name, unicode3: true, length: { maximum: 255 }
  validates :label, unicode3: true, length: { maximum: 255 }

  # S3 limit (w/o multipart upload) is 5GB
  # mysql column limit is 2GB
  validates_numericality_of :size, greater_than_or_equal_to: 1, less_than_or_equal_to: 2.gigabytes

  before_create :choose_storage_provider # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  before_save :destroy_duplicate, if: :replacing_asset # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_save_commit :touch_release_after_save, if: :uploaded_or_updated? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_save :instrument_uploaded_event, if: proc { T.bind(self, ReleaseAsset); state == "uploaded" && state_previously_changed? }
  # rubocop:enable GitHub/AvoidActiveRecordCallbacks
  after_commit :storage_delete_object, on: :destroy # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_destroy_commit :touch_release_after_destroy, if: proc { T.bind(self, ReleaseAsset); state == "uploaded" }
  # rubocop:enable GitHub/AvoidActiveRecordCallbacks
  before_validation :set_guid, on: :create

  delegate :tag_name, to: :release

  enum :state, Storage::Uploadable::STATES

  # BEGIN storage settings

  def registry_package_version
    Platform::LoaderTracker.ignore_association_loads { super } # rubocop:disable GitHub/IgnoreAssociationLoads
  end

  def upload_access_grant(uploader)
    Api::AccessControl.access_grant(
      verb: :edit_release,
      user: uploader,
      repo: repository,
      resource: release,
    )
  end

  def touch_release
    r = release
    r.touch unless r.nil?
  end

  # For after_save_commit and after_destroy_commit callbacks cannot share the same method. Otherwise, the
  # one would overwrite the other and only one would be called.
  def touch_release_after_save
    touch_release
  end

  # For after_save_commit and after_destroy_commit callbacks cannot share the same method. Otherwise, the
  # one would overwrite the other and only one would be called.
  def touch_release_after_destroy
    touch_release
  end

  def storage_policy(actor: nil, repository: nil, key: nil)
    klass = if GitHub.storage_cluster_enabled?
      ::Storage::ClusterPolicy
    else
      ::Storage::MemoryAlphaPolicy
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
      release_id: meta[:release_id],
      label: meta[:label],
    )
  end

  def self.storage_create(uploader, blob, meta)
    storage_new(uploader, blob, meta).tap do |file|
      file.update(state: :uploaded)
    end
  end

  def storage_blob_accessible?
    uploaded?
  end

  def storage_uploadable_attributes
    label.blank? ? {} : { label: label }
  end

  def creation_url
    "#{GitHub.storage_cluster_url}/releases/#{release_id}/files"
  end

  # cluster settings

  def storage_external_url(_ = nil)
    permalink
  end

  # Public: the external url referencing the data represented by this model.
  #   This is NOT a permalink and changes based on the user and request method.
  #
  # current_user       - the actor requesting the url
  # current_repository - the repository the actor is requesting the url for
  # request_method     - one of HEAD or GET based on that which is set in the original user request.
  #
  # Returns a string representation of the external url.
  def direct_external_storage_url(current_user:, current_repository:, request_method:)
    unless %w[GET HEAD].include?(request_method)
      raise ArgumentError, "invalid request method '#{request_method}'. Expected one of GET or HEAD."
    end

    storage_policy = storage_policy(actor: current_user, repository: current_repository)

    if request_method == "HEAD"
      storage_policy.metadata_url
    else
      storage_policy.download_url
    end
  end

  def storage_api_url
    "#{GitHub.api_url}/repositories/#{repository_id}/releases/assets/#{id}"
  end

  def storage_cluster_url(policy)
    creation_url + "/#{id}"
  end

  def storage_cluster_download_token(policy)
    super unless !GitHub.private_mode_enabled? && T.must(repository).public? && T.must(release).published?
  end

  def storage_download_path_info(policy)
    "#{storage_upload_path_info(policy)}/#{id}"
  end

  def storage_upload_path_info(policy)
    "/internal/storage/releases/#{release_id}/files"
  end

  def storage_download_content_type
    served_content_type || DOWNLOAD_CONTENT_TYPE
  end

  def alambic_download_headers(options = nil)
    {
      "Content-Disposition" => served_content_disposition,
    }
  end

  # s3 storage settings

  def self.storage_s3_bucket
    GitHub.s3_environment_config[:asset_bucket_name]
  end

  def self.storage_s3_new_bucket
    "github-#{Rails.env.downcase}-release-asset-2e65be"
  end

  def self.storage_new_fastly_acceleration_bucket
    "github-releases.githubusercontent.com"
  end

  def self.storage_fastly_acceleration_bucket
    "github-cloud.githubusercontent.com"
  end

  def self.memory_alpha_fastly_acceleration_bucket
    GitHub.memory_alpha_fastly_host
  end

  # this method is only used temporarily so we can feature flag in users. once
  # memory alpha is done testing, we can remove this method and go back to either
  # just feature flagging in repos or removing the feature flag altogether.
  def memory_alpha_fastly_acceleration_bucket(actor, repository)
    self.class.memory_alpha_fastly_acceleration_bucket
  end

  # Sorbet gets the type information for this method from `release_asset.rbi` which says `T.nilable(String)`.
  # However, this is overridden in the included `policy.rb` module to return `Symbol`.
  # Due to the order in which signatures are evaluated, Sorbet thinks that calling `storage_provider` in
  # this class should return a nilable String when in fact, due to how ActiveRecord adds attribute accessor
  # methods, Ruby resolves the method to be the module's version.
  # This would all be resolved with an extracted data model but that's a problem for another day.
  # For now, we will help Sorbet along by providing this stub method instead which takes precedence over the
  # rbi file. In my view Sorbet is right to highlight this very confusing code structure as a problem.
  sig { returns(Symbol) }
  def storage_provider
    T.bind(self, T.untyped)
    super
  end

  def storage_fastly_acceleration_bucket(repository)
    if storage_provider == :s3_production_data
      self.class.storage_new_fastly_acceleration_bucket
    else
      self.class.storage_fastly_acceleration_bucket
    end
  end

  def storage_s3_bucket
    if storage_provider == :s3_production_data
      self.class.storage_s3_new_bucket
    else
      self.class.storage_s3_bucket
    end
  end

  def storage_migration_id
    name
  end

  def storage_s3_key(policy)
    if storage_provider == :s3_production_data
      "#{repository_id}/#{guid}"
    else
      "#{GitHub.release_asset_base_path}/#{repository_id}/#{guid}#{self.class.asset_extension(self)}"
    end
  end

  def storage_s3_access_key
    if GitHub.multi_tenant_enterprise?
      GitHub.uploadable_storage_account
    elsif storage_provider == :s3_production_data
      GitHub.release_asset_azure_storage_account
    else
      GitHub.s3_environment_config[:access_key_id]
    end
  end

  def storage_s3_secret_key
    if GitHub.multi_tenant_enterprise?
      GitHub.uploadable_access_key
    elsif storage_provider == :s3_production_data
      GitHub.release_asset_azure_storage_access_key
    else
      GitHub.s3_environment_config[:secret_access_key]
    end
  end

  def storage_s3_download_query(query)
    query["response-content-disposition"] = served_content_disposition
    query["response-content-type"] = served_content_type || DOWNLOAD_CONTENT_TYPE
  end

  def storage_s3_upload_header
    {
      "Content-Type" => "application/octet-stream",
    }
  end

  def storage_upload_expiration
    12.hours
  end

  def storage_transition_ready?
    repository && release && storage_blob_accessible?
  end

  # END storage settings

  def storage_policy_api_url
    "/repositories/%d/releases/assets/%d" % [repository_id, id]
  end

  # Needed for test/lib/github/transitions/20151211173128_enterprise_storage_cluster_upgrade_test.rb
  def alambic_absolute_local_path
    parts = [GitHub.file_asset_path, GitHub.release_asset_base_path]
    parts.push *("%08d" % repository_id).scan(/..../)
    parts << (T.must(guid) + asset_extension)
    parts * "/"
  end

  def self.for(repository, releases)
    return [] if !(repository && releases.present?)
    return [] if releases.any? { |rel| rel.repository_id != repository.id }

    uploaded.where(release_id: releases.map(&:id))
  end

  # Keeps the file extension.  We only care because S3 stores the file with the
  # extension.  When ReleaseAssets are moved to Alambic, we can remove this
  # code.
  def name=(value)
    value_s = value.to_s
    if (old_name = self[:name]).present?
      old_ext = File.extname(old_name)
      if !value_s.downcase.end_with?(old_ext.downcase)
        value_s += old_ext
      end
    end

    @original_name = value_s
    write_attribute :name, sanitize_file_name(value_s)
  end

  # Public: Shows either the asset's label or its filename.
  def display_name
    label.present? ? label : name
  end

  # exposed through the api
  def downloadable_content_type
    if ctype = served_content_type
      ctype
    elsif (ctype = content_type).present?
      ctype
    else
      DOWNLOAD_CONTENT_TYPE
    end
  end

  # controls content type for s3 downloads
  def served_content_type
    CONTENT_TYPE_OVERRIDES[File.extname(name.to_s)]
  end

  def served_content_disposition
    prefix = CONTENT_DISPOSITION_OVERRIDES[File.extname(name.to_s)]
    prefix ||= DEFAULT_CONTENT_DISPOSITION
    if prefix.present?
      "#{prefix} #{filename_content_disposition}"
    else
      filename_content_disposition
    end
  end

  # Public: Absolute permalink URL for this release.
  #
  # Returns a String
  def permalink
    return nil unless repository && release && tag_name

    pieces = tag_name.to_s.split("/")
    pieces.map! { |s| CGI.escape(s) }
    escaped_tag = pieces.join("/")

    "#{T.must(repository).permalink}/releases/download/#{escaped_tag}/#{CGI.escape name.to_s}"
  end

  def uploaded=(value)
    self.state = value ? :uploaded : :starter
    write_attribute :uploaded, value
  end

  def downloads
    slotted_count_with :downloads
  end

  def download
    GitHub.dogstats.increment("release_asset.download.call", tags: ["content_type:#{content_type}"])
    instrument :download, size: size
    slotted_count!(:downloads)
  end

  include Instrumentation::Model
  def event_prefix() :release_assets end

  def denormalize_release
    r = release
    self.repository_id = r.repository_id if r
  end

  def deletion_candidates=(values)
    @deletion_candidates = values.to_s.split(",").map(&:to_i)
  end

  def scheduled_for_deletion?(asset)
    defined?(@deletion_candidates) &&
      @deletion_candidates.include?(asset.id)
  end

  attr_reader :replacing_asset
  attr_reader :replaced_asset

  private

  def choose_storage_provider
    return if GitHub.storage_cluster_enabled?
    self.storage_provider = "s3_production_data"
  end

  def uploader_access
    repo = repository
    if !uploader
      errors.add :uploader_id, "is not a valid User"
    elsif !release
      errors.add :release_id, "is not a valid release"
    elsif !repo
      errors.add :repository_id, "is not a valid repository"
    elsif !repo.resources.contents.writable_by?(uploader)
      errors.add :uploader_id, "does not have push access to #{repo.name_with_owner}"
    end
  end

  # Guidelines for overrides:
  #
  # 1. The extension is used by the user agent.
  # 2. The extension is used to install something.
  # 3. The extension has no known security issues.
  #
  # BAD EXTENSIONS:
  #
  # * exe - No user agent should be running these.
  # * zip - Downloading won't impede the ability to install it.
  # * pdf - Not used to actually install something.
  # * html, css, js, swf, svg - NOOOOPE.  See guideline 3 :)
  CONTENT_TYPE_OVERRIDES = {
    ".apk" => "application/vnd.android.package-archive",
    ".xpi" => "application/x-xpinstall",
  }

  CONTENT_DISPOSITION_OVERRIDES = {
    ".xpi" => "inline;",
  }

  DEFAULT_CONTENT_DISPOSITION = "attachment;"
  DOWNLOAD_CONTENT_TYPE = "application/octet-stream"
  BAD_CONTENT_TYPE = "application/x-www-form-urlencoded"

  def content_type_is_allowed
    self.content_type = DOWNLOAD_CONTENT_TYPE if content_type.blank?
    self.content_type = content_type.strip

    if content_type == BAD_CONTENT_TYPE
      errors.add(:content_type, "can't be #{BAD_CONTENT_TYPE}")
    end
  end

  BAD_EXTENSIONS = Set.new %w(.app .xcarchive)
  def extension_is_allowed
    if BAD_EXTENSIONS.include?(name_extension)
      errors.add(:name, "has a file extension that is not allowed")
    end
  end

  def name_is_unique
    same_named = ReleaseAsset.where(release_id: release_id, name: name)
    same_named = same_named.where("id != ?", self.id) unless new_record?

    if duplicate = same_named.first
      if scheduled_for_deletion?(duplicate) || duplicate.state == "starter"
        @replacing_asset = duplicate.id
      else
        errors.add(:name, :taken, value: name)
      end
    end
  end

  def destroy_duplicate
    ReleaseAsset.destroy(@replacing_asset)
    @replaced_asset = @replacing_asset
    @replacing_asset = nil
  end

  def filename_content_disposition
    "filename=#{name}"
  end

  # Private: runs when the asset is being saved due to being created or updated
  # in order to determine whether to update the associated Release record.
  def uploaded_or_updated?
    state == "uploaded" && (state_previously_changed? || name_previously_changed? || label_previously_changed?)
  end

  def instrument_uploaded_event
    repo = self.repository
    GlobalInstrumenter.instrument("release_asset.uploaded", {
      asset: self,
      release: self.release,
      actor: uploader,
      repository: repo,
      owner: repo&.owner,
    })
  end
end
