# typed: true
# frozen_string_literal: true

require "digest/sha2"
require "s3_sign"
require "github/media_blob"
require "github/sql/readonly"

class Media::Blob < ApplicationRecord::Domain::Assets
  include Storage::FastlyMediaBlobDependency

  BATCH_LIMIT = 100
  STORAGE_SUM_NETWORK_BATCH_SIZE = 10
  STORAGE_SUM_BLOB_BATCH_SIZE = 1000

  include Asset::AlambicCaller

  class CopyError < StandardError
  end

  self.table_name = :media_blobs

  include ::Storage::Uploadable
  include AssetUploadable
  include RawBlob::ContentHelpers
  include Billing::Platform::Api::Utils
  include Repositories::BelongsToRepository

  enum :state, {
    starter:  GitHub::MediaBlob::STARTER,   # 0
    saved:    GitHub::MediaBlob::SAVED,     # 1
    deleted:  GitHub::MediaBlob::DELETED,   # 2
    verified: GitHub::MediaBlob::VERIFIED,  # 3
    archived: GitHub::MediaBlob::ARCHIVED,  # 4
  }

  class << self
    attr_writer :network_copy_batch_size
  end

  def self.network_copy_batch_size
    @network_copy_batch_size ||= 500
  end

  belongs_to :repository_network
  belongs_to :originating_repository, class_name: "Repository"
  belongs_to_repository_via_domain relation_name: :originating_repository, foreign_key: :originating_repository_id, class_name: "Repository", feature_flag: "repos_domain_associations"
  belongs_to :pusher, class_name: "User"
  belongs_to :asset
  belongs_to :storage_blob, class_name: "Storage::Blob"

  validate :storage_ensure_inner_asset, if: :verified?
  validates_presence_of :repository_network_id
  validate :oid_is_non_empty_sha256
  validates_numericality_of :size, greater_than: -1, less_than_or_equal_to: :max_blob_size
  validate :has_asset_status, if: :verified?

  after_destroy :dereference_asset
  after_destroy :storage_remove_from_cluster

  scope :purgeable, -> { where.not(state: :archived) }
  scope :restorable, -> { where(state: :archived) }
  scope :for_repository_network, -> (repo_network) { where(repository_network_id: repo_network.id) }

  # Set true if the blob is a copy of an existing blob, specifically
  # for the case when blobs are copied into a new repository network
  # by ::dup_for_network() after a public repository fork is made private.
  attribute :duplicate, :boolean

  # BEGIN storage settings

  def storage_policy(actor: nil, repository: nil, key: nil)
    klass = if GitHub.storage_cluster_enabled?
      ::Storage::ClusterPolicy
    elsif GitHub.multi_tenant_enterprise?
      ::Storage::LfsPolicy
    else
      ::Storage::S3Policy
    end
    klass.new(self, actor: actor, repository: repository, key: key)
  end

  def self.network_lfs_disk_usage(network_ids)
    result = self.where(repository_network_id: network_ids, state: :verified)
          .group(:repository_network_id)
          .sum(:size)

    network_ids.each_with_object(result) do |network_id, result|
      result[network_id] ||= 0
    end

    result
  end

  # Overrides Storage::Policy::ClassMethods#storage_auth_scope because Git LFS
  # objects do not track the content type.
  def self.storage_auth_scope(meta)
    super(meta.merge(
      original_type: nil,
      content_type: nil,
    ))
  end

  # cluster storage settings

  def self.storage_new(uploader, blob, meta)
    new(
      storage_blob: blob,
      pusher: uploader,
      repository_network_id: meta[:network_id],
      oid: meta[:oid],
      size: meta[:size],
    )
  end

  def self.storage_create(uploader, blob, meta)
    storage_new(uploader, blob, meta).tap do |file|
      file.update(state: :verified)
    end
  end

  def storage_blob_accessible?
    verified?
  end

  def storage_cluster_url(policy)
    "#{GitHub.storage_cluster_url}/lfs/#{policy.repository_id}/objects/#{oid}"
  end

  def storage_upload_path_info(policy)
    "/internal/storage/lfs/#{policy.repository_id}/objects/#{oid}"
  end

  alias storage_download_path_info storage_upload_path_info

  def storage_cluster_download_token(policy)
    super unless !GitHub.private_mode_enabled? && policy.public_repository?
  end

  def storage_cluster_upload_token_params
    { size: size }
  end

  # unnecessary, only downloaded through the lfs api
  def storage_external_url(_ = nil)
  end

  # s3 storage settings

  def storage_s3_key(policy)
    if storage_provider == :s3_production_data || GitHub.multi_tenant_enterprise?
      "#{repository_network_id}/#{oid}"
    else
      ["alambic", alambic_path_prefix, T.must(oid)[0...2], T.must(oid)[2...4], oid].join("/")
    end
  end

  def self.storage_s3_bucket
    GitHub.s3_environment_config[:asset_bucket_name]
  end

  def storage_s3_bucket
    self.class.storage_s3_bucket
  end

  def storage_s3_access_key
    if storage_provider == :s3_production_data
      GitHub.s3_production_data_access_key
    else
      GitHub.s3_alambic_access_key
    end
  end

  def storage_s3_secret_key
    if storage_provider == :s3_production_data
      GitHub.s3_production_data_secret_key
    else
      GitHub.s3_alambic_secret_key
    end
  end

  def storage_download_expiration
    1.hour
  end

  def storage_s3_download_query(query)
    query[:token] = 1
  end

  # alambic storage settings

  def storage_alambic_url(policy)
    "#{GitHub.alambic_assets_url}/media/#{policy.repository_full_name}/object/#{oid}"
  end

  # END storage settings

  def archive
    return false if archived?

    if !verified?
      destroy
      return false
    end

    transaction do
      if asset.nil?
        GitHub::Storage::Destroyer.dereference(self)
      else
        T.must(asset).archive!(self)
      end
      update!(state: :archived)
    end

    true
  end

  def unarchive
    if archived? && has_blob_or_asset?
      transaction do
        if asset.nil?
          GitHub::Storage::Creator.create_uploadable_references([self])
        else
          T.must(asset).reference!(self)
        end
        update!(state: :verified)
      end

      return true
    end

    destroy unless has_blob_or_asset?
    false
  end

  def viewable?
    verified? && (owner_asset_status ? owner_asset_status.active? : true) && (GitHub.storage_cluster_enabled? ? storage_blob : true)
  end

  def owner_asset_status
    @owner_asset_status ||= Asset::Status.lfs.find_by(
      owner_id: responsible_owner_id,
    )
  end

  def emit_storage_usage
    # On GHES we do not track storage cost and on Proxima we are emitting storage
    # events in memory alpha.
    return if GitHub.enterprise? || GitHub.multi_tenant_enterprise?
    return if size < 1

    network = repository_network
    return if network.nil?

    owner = network.owner
    actor = owner.delegate_billing_to_business? ? owner.business : owner
    repo_id = network.root&.id
    organization_id = owner.is_a?(Organization) ? owner.id : nil
    GlobalInstrumenter.instrument("billing_platform.metered_usage", {
      sku: "git_lfs_storage",
      quantity: (size.to_f / (1024.0**3)).round(9),
      usage_at:  Google::Protobuf::Timestamp.new(seconds: Time.now.to_i, nanos: 0),
      source_uri: "gid://git-hub/Repository/#{repo_id}",
      entity: {
        customer_id: actor.feature_flag_enabled?(:use_find_or_create_customer, default: true) ? actor.find_or_create_customer.id : (actor.customer&.id || 0),
        repo_id: repo_id,
        organization_id: organization_id,
        actor_id: actor.id,
      },
    })
  end

  def set_verified_state!
    Asset.store(self) do |asset|
      asset.unarchive!(self) if archived?
      self.asset = asset
      self.state = :verified
      raise ActiveRecord::RecordInvalid.new(self) unless valid?

      num = self.class.
        where(id: id, oid: oid, size: size).
        where("(asset_id is null or asset_id = ?)", asset_id).
        update_all(asset_id: asset_id, state: self.class.states[T.must(state)])

      if num != 1
        errors.add(:base, "Size or File mismatch: #{num.inspect}")
        raise ActiveRecord::RecordInvalid.new(self)
      end
    end
    emit_storage_usage
  end

  def verify!
    if !verified?
      http = Faraday.new(url: verify_url) do |b|
        if test_block = self.class.verify_test_block
          b.adapter(:test, &test_block)
        else
          b.adapter Faraday.default_adapter
        end
      end

      res = http.head(verify_url)
      if res.status != 200
        return false
      end
      set_verified_state!
    end
    true
  end

  def has_blob_or_asset?
    storage = if GitHub.storage_cluster_enabled?
      storage_blob
    else
      asset
    end

    storage.present?
  end

  def self.verify_test_block
    @verify_test_block
  end

  def self.reset_verify_test!
    @verify_test_block = nil
  end

  def self.stub_verify_test(blob, &block)
    prefix = GitHub.multi_tenant_enterprise? ? "/git-lfs" : ""
    @verify_test_block = lambda do |stub|
      stub.head("#{prefix}/#{blob.storage_s3_key(nil)}", &block)
    end
  end

  def self.surrogate_key_for(branch, path)
    hash = Digest::SHA256.new
    hash << Digest::SHA256.digest(branch)
    hash << " "
    hash << Digest::SHA256.digest(path)
    "media/#{hash}"
  end

  # Public: Counts the used storage for an owner.  This is potentially a slow
  # query, so it should be called from jobs and not live requests.
  #
  # NOTE: Unusable for GHE Storage Cluster since unique OIDs across multiple
  # repository networks are counted.
  #
  # owner  - A User or Organization.
  # network_batch_size - Number of repository networks in each query (optional).
  # blob_batch_size    - Number of blob objects in each query (optional).
  #
  # Returns the Integer total storage in bytes.
  def self.storage_by_owner(owner,
    network_batch_size: STORAGE_SUM_NETWORK_BATCH_SIZE,
    blob_batch_size: STORAGE_SUM_BLOB_BATCH_SIZE
  )
    network_ids = possible_lfs_network_ids(owner)
    blob_total_size = T.let(0, Numeric)

    ActiveRecord::Base.connected_to(role: :reading) do
      network_ids.in_groups_of(network_batch_size) do |ids|
        batch_network_ids = ids.compact
        next if batch_network_ids.blank?

        batch_blob_total_size = storage_by_networks(batch_network_ids, blob_batch_size: blob_batch_size)

        blob_total_size += batch_blob_total_size
      end
    end

    blob_total_size
  end

  def self.storage_by_networks(network_ids, blob_batch_size: STORAGE_SUM_BLOB_BATCH_SIZE)
    blob_total_size = T.let(0, Numeric)

    # We only have one index that will suffice here as a covering index, the
    # index_media_blobs_on_state_repo_network_id_created_at_and_size index,
    # which for historical reasons contains the created_at column,
    # although it is no longer required.
    # Since the id column is automatically appended as the last part of
    # any index, we can use this to sort our records in a fixed order
    # even if they have the same repository_network_id, created_at, and
    # size values, and so we are able to step through them in batches.
    sql = <<-SQL
    WITH blobs AS (
        SELECT repository_network_id, created_at, size, id
          FROM media_blobs
         WHERE repository_network_id IN (:network_ids)
           AND state = :state
           AND (repository_network_id > :last_repository_network_id OR
                (repository_network_id = :last_repository_network_id AND
                 (created_at > :last_created_at OR
                  (created_at = :last_created_at AND
                   (size > :last_size OR
                    (size = :last_size AND id > :last_id))))))
         ORDER BY repository_network_id, created_at, size, id
         LIMIT :batch_size
      ),
      last_blobs AS (
        SELECT repository_network_id AS last_repository_network_id,
               created_at AS last_created_at, size AS last_size, id AS last_id
          FROM blobs
         ORDER BY repository_network_id DESC, created_at DESC,
                  size DESC, id DESC
         LIMIT 1
      )
    SELECT SUM(size) AS blob_total_size, COUNT(*) AS blob_count,
           last_repository_network_id, last_created_at, last_size, last_id
      FROM blobs
      JOIN last_blobs
    SQL

    last_repository_network_id = T.let(0, T.untyped)
    last_created_at = Time.new(2000, 1, 1)
    last_size = T.let(0, T.untyped)
    last_id = T.let(0, T.untyped)

    ActiveRecord::Base.connected_to(role: :reading) do
      while true do
        sql_bindings = {
          network_ids: network_ids,
          state: states[:verified],
          last_repository_network_id: last_repository_network_id,
          last_created_at: last_created_at,
          last_size: last_size,
          last_id: last_id,
          batch_size: Arel.sql(blob_batch_size.to_s),
        }

        query = Arel.sql(sql, **sql_bindings)
        row = Media::Blob.connection.select_rows(query).first
        break if row.nil? || row[0].nil?

        # ActiveRecord reports SUM() values as BigDecimal objects, so we
        # convert them to integers before adding them to our total, the
        # same way the #sum() method implicitly converts them using
        # ActiveModel::Type::Integer#deserialize().
        blob_total_size += row[0].to_i
        break if row[1] < blob_batch_size

        last_repository_network_id = row[2]
        last_created_at = row[3]
        last_size = row[4]
        last_id = row[5]
      end
    end

    blob_total_size
  end

  # Public
  def self.lfs_repositories(owner)
    Platform::Loaders::LfsRepositories.load(owner.id).sync
      .tap { |repos| Repository.prefill_associations(repos) }
  end

  def self.lfs_repositories_for_owner(owner)
    repository_scope = owner.repositories
      .where(active: true, parent_id: nil, locked: false)

    source_ids = repository_scope.pluck(:source_id)

    network_ids = ::Media::Blob.verified.distinct.where(repository_network_id: source_ids).pluck(:repository_network_id)

    repository_scope.where(source_id: network_ids)
  end

  # Internal
  def self.possible_lfs_network_ids(owner)
    owner.repositories
      .where(active: true, parent_id: nil, locked: false)
      .group(:source_id)
      .pluck(Arel.sql("/*vt+ IGNORE_MAX_MEMORY_ROWS=1 */ source_id"))
  end

  def self.update_status_for_repository_transfer(repository, new_owner:, old_owner:)
    return unless in_network?(repository.network)
    new_owner.build_asset_status!
    new_owner.asset_status.rebuild
    old_owner.build_asset_status!
    old_owner.asset_status.rebuild
  end

  def self.in_network?(repository_network)
    !find_by(repository_network_id: repository_network.id).nil?
  end

  # Public: Gets the Media::Blob.
  #
  # repository - The Repository that is getting the Git LFS blob.  Note: the
  #              blob is actually stored with the RepositoryNetwork so it is
  #              accessible by any forks.
  # oid        - String ID of the content.  Should be a SHA-256 signature of the
  #              raw content.
  #
  # Returns a Media::Blob or nil if not found.
  def self.fetch(repository, oid)
    find_by(repository_network_id: repository.network_id, oid: oid)
  end

  # Public: Gets all Media::Blob objects for the given oids.
  #
  # repository - The Repository that is getting the Git LFS blob.  Note: the
  #              blob is actually stored with the RepositoryNetwork so it is
  #              accessible by any forks.
  # oid        - Array of String ID of the objects.
  #
  # Returns an Array of Media::Blob objects.
  def self.fetch_all(repository, oids)
    return [] if oids.blank?

    if oids.size > BATCH_LIMIT
      raise ArgumentError, "Expected up to 100 objects, got #{oids.size}."
    end

    where(repository_network_id: repository.network_id, oid: oids.uniq)
  end

  def self.fetch_by_id(repository, id)
    blob = find_by(id: id.to_i)
    blob && blob.in?(repository) && blob
  end

  # Public: Gets a page of Media::Blob records based on the given OID.
  def self.page(repository, oid: nil)
    cond = if oid
      ["repository_network_id = ? AND oid > ?", repository.network_id, oid]
    else
      ["repository_network_id = ?", repository.network_id]
    end

    # By default MySQL uses index_media_blobs_on_oid_and_network_repository_id.
    # That means it scans through the entire OID space in that index to find
    # 50 repository network IDs that match. This can take a long time.
    # Force MySQL to use `index_media_blobs_on_repository_network_id` instead
    # to find the Media Blobs quickly and then sort the results in memory.
    from("#{Media::Blob.quoted_table_name} USE INDEX (index_media_blobs_on_repository_network_id)").where(cond).order("oid").limit(50)
  end

  # Check if the current repository is allowed to proceed with usage of the given SKU
  def self.budget_exceeded?(sku:, repository:, actor:)
    return false if GitHub.enterprise?

    network = repository.network || raise(GitHub::DataQualityError.new(repository, :network))
    owner = network.owner || raise(GitHub::DataQualityError.new(network, :owner))
    billing_entity = owner.delegate_billing_to_business? ? owner.business : owner

    customer_id = owner.feature_flag_enabled?(:use_find_or_create_customer, default: true) ? owner.find_or_create_customer.id : (billing_entity.customer&.id || 0)

    # Individual repositories do not "own" LFS objects. LFS objects belong to
    # the repository network. Since the concept of repository networks is not
    # exposed to the billing platform, we use the root repository here. That
    # means all LFS usage is presented on the website using the root
    # repository.
    entity_detail = BillingPlatform::Base::EntityDetail.new(
      customerId: customer_id.to_s,
      repoId: network.root.id,
      ownerId: owner.id,
      actorId: actor&.id)

    # See products/skus in https://github.com/github/billing-platform/blob/main/lib/engines/pricing.go#L229
    # We also could set the expected quantity for the usage here but this value
    # is ignored by the billing platform right now anyways.
    usage_key = BillingPlatform::Api::V1::UsageKey.new(
      product: "git_lfs",
      sku: sku,
      entityDetail: entity_detail)

    response = Billing::Platform::Api::Client.new(timeout: 3.seconds).can_proceed_with_usage(usage_key: usage_key)

    if response.is_a?(Hash) && response.has_key?(:canProceed)
      GitHub.dogstats.increment("lfs.billing.can_proceed_with_usage", tags: [
        "success:true",
        "can_proceed:#{response[:canProceed]}"
      ])
      return !response[:canProceed]
    end

    GitHub.dogstats.increment("lfs.billing.can_proceed_with_usage", tags: ["success:false"])

    if response.is_a?(Billing::Platform::Api::Error)
      GitHub.dogstats.increment("billing.lfs.error", tags: ["context:budget_exceeded_method", "exception:#{response.class.name}"])
      GitHub.logger.error("Billing platform error", {
        exception: response,
        "gh.customer.id": customer_id,
        "gh.owner.id": owner.id,
        "gh.repo.id": repository.id,
      })
    else
      GitHub.dogstats.increment("billing.lfs.error", tags: ["context:budget_exceeded_method", "exception:KeyError"])
      response_keys = response.keys.join(",") if response.is_a?(Hash)
      GitHub.logger.error("Unexpected billing platform error", {
        exception: KeyError.new("key not found: :canProceed"),
        "gh.billing.can_proceed_with_usage.result.type": response.class.name,
        "gh.billing.can_proceed_with_usage.result.keys": response_keys,
        "gh.customer.id": customer_id,
        "gh.owner.id": owner.id,
        "gh.repo.id": repository.id,
      })
    end

    false
  end

  def self.over_quota?(repo)
    false
  end

  def self.init_all(repository, pusher:, objects:)
    blob = T.let(new(repository_network_id: repository.network_id), Media::Blob)
    blob.build_asset_status!

    oids = objects.map { |o| o[:oid] }
    blobs_by_oid = ActiveRecord::Base.connected_to(role: :reading) { fetch_all(repository, oids).index_by(&:oid) }

    new_oids = []
    rows = []
    now = blob.send(:current_time_from_proper_timezone)
    objects.each do |obj|
      oid, size = obj.values_at :oid, :size
      blob = blobs_by_oid[oid] ||= new(
        storage_blob: ::Storage::Blob.new(size: size, oid: oid),
        oid: oid,
        pusher: pusher,
        state: :starter,
        repository_network_id: repository.network_id,
        originating_repository_id: repository.id,
      )
      blob.size = size

      if blob.verified? || blob.archived?
        blob.errors.add(:size, "cannot change") if blob.size_changed?
      elsif blob.valid?
        new_oids << blob.oid
        rows << [
          blob.oid, blob.size, states[:saved], blob.pusher_id || 0,
          blob.repository_network_id, blob.originating_repository_id, now
        ]
      end
    end

    if rows.any?
      self.connection.insert(Arel.sql(<<-SQL, rows: Arel::Nodes::ValuesList.new(rows)))
        INSERT INTO media_blobs (`oid`, `size`, `state`, `pusher_id`,
          `repository_network_id`, `originating_repository_id`, `created_at`)
        :rows
        ON DUPLICATE KEY UPDATE
          `size` = IF(`state` = #{states[:verified]}, `size`, VALUES(`size`))
      SQL

      fetch_all(repository, new_oids).each do |blob|
        blobs_by_oid[blob.oid] = blob
      end
    end

    oids.map { |o| blobs_by_oid[o] }
  end

  # Public: Links a Git LFS blob to a Repository.  Creates the related records
  # as needed.
  #
  # repository - The Repository that is getting the Git LFS blob.  Note: the
  #              blob is actually stored with the RepositoryNetwork so it is
  #              accessible by any forks.
  # oid        - String ID of the content.  Should be a SHA-256 signature of the
  #              raw content.
  # meta       - Hash of the asset's meta data.  See Asset.upload for expected
  #              Asset meta values.
  #              :pusher - The User record that is uploading the asset.
  #
  # Returns a Media::Blob.
  def self.upload(repository, oid, meta)
    GitHub.dogstats.increment("media_blob.upload")
    meta ||= {}
    # these meta values are ignored by Asset, but used in Media::Blob#after_upload.
    meta[:uploadable] = {
      repository: repository,
      pusher: meta.delete(:pusher),
    }

    media_blob = fetch(repository, oid)

    # If an archived model exists, we know the asset was uploaded and verified
    # once. We don't need to set the Asset meta data.  But we should require the
    # user to re-upload the file.
    if media_blob.try(:archived?)
      asset = media_blob.asset

      transaction do
        asset.unarchive!(media_blob)
        media_blob.update!(state: :saved)
      end

      return media_blob
    end

    Asset.upload(media_blob, oid, meta) do |asset|
      blob = create!(asset: asset, oid: oid, size: asset.size,
        charset: asset.charset, state: :saved,
        repository_network_id: repository.network_id)
      blob.build_asset_status!
      blob
    end
  end

  def self.auth_token(user, meta)
    user.signed_auth_token(scope: auth_scope(meta), expires: 1.hour.from_now)
  end

  def self.auth_scope(meta)
    "%s:%d:%s:%s" % [auth_scope_prefix, meta[:repository_id].to_i, meta[:committish], meta[:path]]
  end

  def self.auth_scope_prefix
    "Asset:%s" % self.name
  end

  def self.auth_scope_options(repository, committish, path)
    { repository_id: repository.id, committish: committish, path: path }
  end

  def self.pointer(data)
    return unless data
    Media::Pointer.parse(data.to_s)
  end

  def self.pointers_from_diff(diff)
    Media::Pointer.parse_diff(diff)
  end

  def public?
    root_repository.public?
  end

  def alambic_download_headers(options = nil)
    options ||= {}
    origin = options[:origin]&.to_s

    allowed_origin = CodeRenderingService::OriginUrlResolver.host_url(origin)

    head = {
      "Access-Control-Allow-Origin" => allowed_origin
    }

    if max_age = options[:max_age]
      head["Cache-Control"] = "max-age=#{max_age.to_i}"
    end

    if path = options[:path]
      head["Surrogate-Key"] = "media/#{path}"
    end

    head
  end

  def self.dup_for_network(blobs, new_network)
    Array(blobs).map do |blob|
      Media::Blob.create!(
        asset_id: blob.asset_id,
        storage_blob_id: blob.storage_blob_id,
        repository_network_id: new_network.id,
        oid: blob.oid,
        size: blob.size,
        charset: blob.charset,
        state: blob.state,
        originating_repository_id: blob.originating_repository_id,
        pusher_id: blob.pusher_id,
        duplicate: true
      )
    end
  end

  def self.copy_for_network(transition, blobs, network)
    blobs = blobs.reject { |b| b.repository_network_id == network.id }
    unverified_blobs = blobs.reject { |b| b.verified? }
    if unverified_blobs.any?
      GitHub.dogstats.increment("lfs.copy_for_network.unverified_blobs")
      GitHub.logger.info("LFS blobs in repository network not copied due to unverified blobs", {
                           "code.namespace":     "Media::Blob",
                           "code.function":      "copy_for_network",
                           "gh.repo.network.id": transition.repository_network.id,
                         })
      return
    end

    return if blobs.blank?

    if !GitHub.storage_cluster_enabled?
      blobs.each do |b|
        b.copy_for_network(transition, network)
      end
      return
    end

    transaction do
      new_blobs = dup_for_network(blobs, network)
      GitHub::Storage::Creator.create_uploadable_references(new_blobs)
    end
  end

  # Internal: Copies the given Media::Blob into a new RepositoryNetwork.
  def copy_for_network(transition, new_network)
    res = http.post("/media/transitions") do |req|
      json = {
        transition_id: transition.id,
        blob_id: id,
        operation: transition.operation,
      }.to_json

      req.headers.update(
        "Content-Type" => "application/json",
        "Content-HMAC" => Api::Internal.content_hmac(json),
      )
      req.body = json
    end

    if res.status != 200
      raise CopyError, "Unsuccessful response for blob ID #{id}, OID #{oid}: #{res.status}"
    end

    new_blobs = self.class.dup_for_network([self], new_network)
    new_blobs.each { |b| T.must(asset).reference!(b) }
  end

  def safe_repository_network
    repository_network || raise(GitHub::DataQualityError.new(self, :repository_network))
  end

  def root_repository
    safe_repository_network.root || raise(GitHub::DataQualityError.new(self, :root_repository))
  end

  def repository_network_owner
    root_repository.plan_owner || raise(GitHub::DataQualityError.new(self, :plan_owner))
  end

  def root_repository_id
    root_repository.id
  end

  def repository_network_owner_id
    repository_network_owner.id
  end

  def responsible_owner_id
    repository_network_owner_id
  end

  # Deprecated: Legacy location of the file on GHE before the storage cluster
  # GitHub.storage_legacy_path => "/data/user/alambic_assets/shared"
  # /data/user/alambic_assets/shared/media/{id}/ab/cd/abcdef1234567890
  def alambic_absolute_local_path
    File.join(GitHub.storage_legacy_path, alambic_path_prefix, T.must(oid)[0...2], T.must(oid)[2...4], oid)
  end

  def alambic_path_prefix
    @alambic_path_prefix ||= "media/#{repository_network_id}"
  end

  def after_upload(meta)
    uploadable = meta[:uploadable]
    repo = uploadable && uploadable[:repository]
    pusher = uploadable[:pusher]
    if repo.nil? || pusher.nil?
      raise ArgumentError, "Expected :repository and :pusher in #{uploadable.inspect}"
    end

    self.pusher_id ||= pusher.id
    self.originating_repository_id ||= repo.id

    T.must(asset).update_meta(meta)
    save!
  end

  attr_accessor :path

  def content_type
    @content_type ||= raw_mime_for(@path)
  end

  def etag
    oid
  end

  def updated_at
    nil
  end

  # Only 1 Media::Blob exists per repository network, each with its own distinct
  # path prefix.  Therefore, always archive after deleting a media blob.
  def archive?(asset)
    asset.id == asset_id
  end

  def in?(repo)
    repository_network_id.to_i == (repo.try(:network_id) || repo.id)
  end

  def self.each_network_batch(network, last_id: nil, batch_size: network_copy_batch_size, readonly: false)
    network_id = network.respond_to?(:id) ? network.id : network.to_i
    start = last_id.nil? ? nil : last_id.to_i + 1
    enum = from("`media_blobs` IGNORE INDEX FOR ORDER BY (PRIMARY)").
      where(repository_network_id: network_id).
      find_in_batches(start: start, batch_size: batch_size)
    enum = GitHub::SQL::Readonly.new(enum) if readonly
    T.must(enum).each { |b| yield b }
  end

  def download_url(actor: nil, repo:)
    storage_policy(actor: actor, repository: repo).download_url
  end

  def verify_url
    storage_policy.metadata_url(use_cdn: false)
  end

  def download_link(actor: nil, repo:, key: nil)
    link = storage_policy(actor: actor, repository: repo, key: key).download_link
    if GitHub.storage_cluster_enabled? && GitHub.storage_cache_location_url
      link[:href].sub!(GitHub.storage_cluster_url, GitHub.storage_cache_location_url)
    end
    link
  end

  def lfs_upload_link(actor: nil, repo:, key: nil)
    policy = storage_policy(actor: actor, repository: repo, key: key)
    now = Time.now
    policy.lfs_upload_link
  ensure
    policy.stats_timing(:upload, start: now) if now && policy
  end

  def verify_token(user, repo, key = nil)
    Media::Token.gitauth_token_for_actor(user || key, verify_scope, repo, 1.day.from_now)
  end

  def self.verify_scope(repository_network_id, oid)
    "LFS:verify:%d:%s" % [repository_network_id, oid]
  end

  def verify_scope
    self.class.verify_scope(repository_network_id, oid)
  end

  def build_asset_status!
    if user = User.find_by(id: responsible_owner_id.to_i)
      user.build_asset_status!
    else
      raise "invalid user: #{responsible_owner_id.inspect}"
    end
  end

  def self.s3_credentials
    {
      bucket: GitHub.s3_environment_config[:asset_bucket_name],
      key: GitHub.s3_alambic_access_key,
      secret: GitHub.s3_alambic_secret_key,
    }
  end

  def self.stub_copy(&block)
    stub_http do |stub|
      stub.post("/media/transitions", &block)
    end
  end

  def self.stub_copy!
    stub_copy do |env|
      verify_env = {
        Api::Internal::REQUEST_METHOD => "POST",
        Api::Internal::CONTENT_HMAC_KEY => env[:request_headers]["Content-HMAC"],
      }
      hmac_status = Api::Internal.verify_content_hmac(verify_env, env[:body])
      body = JSON.parse env[:body]
      transition = Media::Transition.find_by(id: body["transition_id"].to_i)
      blob = Media::Blob.find_by(id: body["blob_id"].to_i)

      if hmac_status != :success
        [403, {}, "bad hmac: #{hmac_status}"]
      elsif transition.nil?
        [422, {}, "no transition"]
      elsif blob.nil?
        [422, {}, "no blob"]
      elsif blob.repository_network_id != transition.old_repository_network_id
        [422, {}, "different networks"]
      elsif body["operation"] != "copying"
        [422, {}, "operation #{body["operation"]} failed"]
      else
        [200, {}, "ok"]
      end
    end
  end

  private

  EMPTY_OID = "0" * 64

  def oid_is_non_empty_sha256
    if oid.blank?
      errors.add(:oid, "is required")
    elsif oid == EMPTY_OID || oid !~ /\A[0-9A-F]{64}\Z/i
      errors.add(:oid, "is invalid")
    end
  end

  def has_asset_status
    return if deleted?
    return if errors.any?
    if user = User.find_by(id: responsible_owner_id.to_i)
      user.build_asset_status!
    else
      errors.add :base, "invalid user: #{responsible_owner_id.inspect}"
    end
  end

  def max_blob_size
    # If we are copying, archiving, or unarchiving existing blobs, we
    # need to default to the largest possible value so that we don't fail
    # validation for large blobs.
    return MAX_ASSET_SIZE if duplicate? || !new_record?
    # We should always have a repository root except when the network has been
    # destroyed and we're archiving blobs, in which case #new_record?() should
    # have been true.  However, to be safe, we confirm the network's root
    # repository exists and has a non-zero maximum blob size limit before
    # returning that limit.
    max_size = repository_network&.root&.plan_limit(:media_blob_max_size)
    max_size && max_size > 0 ? max_size : MAX_ASSET_SIZE
  end
end
