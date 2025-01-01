# typed: false
# frozen_string_literal: true

# Joins an owner (User, Org, Business, etc) to the avatar that's actively being shown.
class PrimaryAvatar < ApplicationRecord::Domain::Users
  # storage settings are in Avatar::Shared
  include ::Storage::Uploadable

  include Avatar::Shared
  include Instrumentation::Model

  belongs_to :avatar
  belongs_to :previous_avatar, class_name: "Avatar"
  belongs_to :updater, class_name: "User"
  belongs_to :owner, -> { including_deleted }, polymorphic: true
  validate :can_update
  validates_presence_of :avatar_id, :owner_id, :owner_type, :updater_id
  validates_uniqueness_of :owner_id, scope: :owner_type

  before_destroy :destroy_avatars

  after_commit :update_keys_in_cdn
  after_commit :purge_keys_from_cdn, on: :destroy
  after_commit :instrument_update

  FASTLY_DICTIONARY_KEY_NAME = "key1"
  DEFAULT_EXPIRATION_TIME = 20.minutes
  TIMESTAMP_BUCKET_LENGTH = 15.minutes
  NUMBER_OF_PARALLEL_BUCKETS = 15

  # Returns the first part of the avatar URL which can can be different
  # depending if multi tenancy is enabled or not
  def self.alambic_avatar_url(entity = nil)
    # if feature flag is enabled, return private avatar URL if exists
    return GitHub.alambic_private_avatar_url || GitHub.alambic_avatar_url if current_actor_private_avatar_enabled?
    # if no multi tenant, return whatever is configured
    return GitHub.alambic_avatar_url unless GitHub.multi_tenant_enterprise?

    tenant = nil
    if entity
      begin
        tenant = entity.tenant_slug_for_avatar
      rescue NotImplementedError
        GitHub.logger.warn(
          "`tenant_slug_for_avatar` not implemented for entity",
          "code.namespace" => self.name,
          "code.function" => __method__,
          "gh.avatars.entity.class" => entity.class.name,
          "gh.avatars.path" => entity.primary_avatar_path)
      end
    end

    # In the event that an entity is not supplied, an entity is unable to report its tenant slug, or the tenant slug
    # is the company-specific entity acronym, we default to the current tenant. In the case of the company-specific
    # entity acronym, we do this because system accounts (like the "@ghost" account) are not attached to tenants and
    # rely on the `entity` query parameter sent to Alambic to validate the request. Using the company-specific entity
    # can result in DNS resolution not working (i.e. when the `GitHub.company_specific_entity_acronym` is not a valid
    # subdomain).
    if tenant.nil? || tenant == GitHub.company_specific_entity_acronym
      tenant = GitHub::CurrentTenant.get&.slug
    end

    return generate_tenant_based_url(tenant) if tenant

    # TODO: We might be in a multi tenant environment but without having a defined tenant,
    # we just return a relative URL. We might need to fix this edge cases in the future
    # but its unclear if we will never reach that code path Today, but better to not break the
    # whole code path by just returning a relative URL as we were already doing until
    # this change.
    "/avatars"
  end

  # Returns a Hash of URI query arguments for avatars.
  #
  # path - String path for the avatars service. Typically from implementations
  #        of #primary_avatar_path. Example: "/user/123"
  # size - Optional integer specifying a dynamic size for the avatar.
  # uniq - Optional string representing a unique hash for this avatar. This
  #        should change if the content of the avatar changes, not including
  #        dynamic sizing.
  def self.query_for(path, size: nil, uniq: nil)
    q = {}
    if v = GitHub.avatar_version(path)
      q[:v] = v
    end

    if b = GitHub.browser_avatar_version(path)
      q[:b] = b
    end

    q[:s] = size.to_i if size
    q[:u] = uniq.to_s if uniq
    q
  end

  # Returns a full avatar url for the given path and query parameters.
  #
  # path -   String path for the avatars service. Typically from implementations
  #          of #primary_avatar_path. Example: "/user/123"
  # size -   Optional integer specifying a dynamic size for the avatar.
  # uniq -   Optional string representing a unique hash for this avatar. This
  #          should change if the content of the avatar changes, not including
  #          dynamic sizing.
  # entity - Optional model that includes PrimaryAvatar::Model. Only used in multi tenant mode
  def self.url_for(path, size: nil, uniq: nil, entity: nil)
    q = query_for(path, size: size, uniq: uniq)
    q = add_token_and_entity_to_query(q, entity, path) if GitHub.multi_tenant_enterprise?
    q = add_jwt_token_to_query(q, path) if current_actor_private_avatar_enabled?

    path += "?#{q.to_query}" unless q.empty?
    "#{alambic_avatar_url(entity)}#{path}"
  end

  # Public: Build a new PrimaryAvatar from a given Avatar.
  #
  # avatar - Saved Avatar model.
  #
  # Returns a new, unsaved PrimaryAvatar.
  def self.build(avatar)
    new(owner: avatar.owner)
  end

  # Public: Gets the primary avatar for the owner.
  #
  # owner - An ActiveRecord model that owns an avatar.  Likely a User or
  # Organization.
  #
  # Returns a PrimaryAvatar
  def self.get(owner)
    find_by(owner_id: owner.id, owner_type: owner.class.base_class.name)
  end

  # Public: Sets the given avatar as the primary avatar for the avatar's owner.
  # This will retry once from an `owner_id` constraint failure.  Last write wins.
  #
  # avatar - An Avatar.
  # updater - The User that is setting the avatar.
  #
  # Returns a PrimaryAvatar.
  def self.set!(avatar, updater, handle_previous_avatar: true)
    set(avatar, updater, handle_previous_avatar: handle_previous_avatar)
  rescue ActiveRecord::RecordInvalid
    set(avatar, updater, handle_previous_avatar: handle_previous_avatar)
  end

  # Public: Sets the given avatar as the primary avatar for the avatar's owner.
  # Note: This does not rescue from an `owner_id` constraint failure.
  #
  # avatar - An Avatar.
  # updater - The User that is setting the avatar.
  #
  # Returns a PrimaryAvatar.
  def self.set(avatar, updater, handle_previous_avatar: true)
    primary = get(avatar.owner) || build(avatar)
    transaction do
      primary.set(avatar, updater)
      avatar.owner.try(:handle_previous_avatar, primary) if handle_previous_avatar
    end
    primary
  end

  # Genetares a token that will be used in Proxima, so alambic can validate the request is coming from an anthenticated
  # and authorized user.
  def self.generate_token_for(tenant, path)
    timestamp = Time.now.to_i.to_s
    data = "AvatarFetcher/#{timestamp}/#{tenant}/#{path}"
    hmac = OpenSSL::HMAC.hexdigest(GitHub::RequestHmacValidator::HMAC_ALGORITHM, GitHub.alambic_avatars_hmac_key.to_s, data)

    Base64.strict_encode64("#{timestamp}.#{hmac}")
  end

  def self.add_token_and_entity_to_query(query, entity, path)
    if entity
      begin
        tenant = entity.tenant_slug_for_avatar.downcase
        return query unless tenant
      rescue NotImplementedError
        # Models that include the `PrimaryAvatar::Model` module but do not implement the `tenant_slug_for_avatar` method
        # are not supported in Proxima. This is the case for some models, such as Listing, and we
        # don't need generate tokens for them.
        return query
      end
    else
      # We have internal calls to `#PrimaryAvatar.url_for` that are made from `#AvatarHelper.direct_avatar_link` and have
      # the user handlers hardcoded. In these cases, we treat the calls as if they were made to company-specific entities,
      # since we don't have an entity object to work with. This means that the `entity` parameter will be `nil`.
      tenant = GitHub.company_specific_entity_acronym
    end

    token = generate_token_for(tenant, path)

    inter_q = { token: token }

    # System accounts, such as the "@ghost" account, are not attached to tenants and do not have a tenant slug.
    # In Alambic, we want to skip the regular HMAC check for these accounts and validate them directly against
    # GitHub.company_specific_entity_acronym, which is the default entity acronym for system accounts.
    inter_q = inter_q.merge(entity: tenant) if tenant == GitHub.company_specific_entity_acronym

    query.merge(inter_q) unless token.empty?
  end

  def self.calculate_nbf(path)
    # nbf value needs to be bucketed to provide less changing tokens
    # To achieve this, we bucket the nbf value and change them after TIMESTAMP_BUCKET_LENGTH
    # There are also parallel buckets that starts after each other with an offset
    t = Time.now
    bucket_index = Zlib.crc32(path) % NUMBER_OF_PARALLEL_BUCKETS
    offset = (TIMESTAMP_BUCKET_LENGTH / NUMBER_OF_PARALLEL_BUCKETS) * bucket_index
    TIMESTAMP_BUCKET_LENGTH * ((t - offset).to_i / TIMESTAMP_BUCKET_LENGTH) + offset
  end

  def self.generate_tenant_based_url(tenant_slug)
    # Local multi-tenant development makes use of the `GitHub.host_name` configuration value, multi-tenant
    # production does not. `GitHub.host_name` should correspond to the stamp URI and requires some modification
    # to add the tenant slug subdomain to it.
    if Rails.env.development?
      gh_uri = URI.parse("#{GitHub.ssl ? "https" : "http"}://#{GitHub.host_name}")
      args = { host: "#{tenant_slug}.#{gh_uri.host}", port: gh_uri.port, path: "/alambic/avatars" }
      if GitHub.ssl
        return URI::HTTPS.build(args).to_s
      else
        return URI::HTTP.build(args).to_s
      end
    end

    "https://#{tenant_slug}.ghe.com/avatars"
  end

  def self.generate_jwt_token_for(path)
    nbf = calculate_nbf(path)
    exp = nbf + DEFAULT_EXPIRATION_TIME

    payload = {
      # The 'iss' and 'aud' values are used by code scanning to filter the private assets JWT out from its results.
      # If these values need to be changed, please make sure to align it with the code scanning team. Also, 'iss'
      # and 'aud' MUST be in this order and at beginning of the payload, so a pattern can be maintained during the
      # encoding.
      iss: "github.com",
      aud: "raw.githubusercontent.com",
      key: FASTLY_DICTIONARY_KEY_NAME,
      exp: exp.to_i,
      nbf: nbf.to_i,
      path: "#{path}"
    }
    JWT.encode(payload, GitHub.private_avatars_cdn_key, "HS256", { typ: "JWT" })
  end

  def self.add_jwt_token_to_query(query, path)
    query.merge(jwt: generate_jwt_token_for(path))
  end

  def self.current_actor_private_avatar_enabled?
    return false if GitHub.multi_tenant_enterprise?
    # Following is a workaround to avoid n+1 query issue when doing the feature flag check
    return GitHub.context[:current_actor_private_avatar_enabled] if
      GitHub.context[:current_actor_private_avatar_enabled] != nil
    private_avatar_enabled = User.new(id: GitHub.context[:actor_id]).feature_enabled?(:private_avatars)
    GitHub.context.push(current_actor_private_avatar_enabled: private_avatar_enabled)
    private_avatar_enabled

  end

  def set(new_avatar, updater)
    update! avatar: new_avatar, updater: updater,
      previous_avatar: self.avatar,
      cropped_x: new_avatar.cropped_x, cropped_y: new_avatar.cropped_y,
      cropped_width: new_avatar.cropped_width, cropped_height: new_avatar.cropped_height
    owner.touch
  end

  def same_as_previous?
    previous_avatar_id == avatar_id
  end

  def avatar_oid
    avatar.try(:avatar_oid)
  end

  def content_type
    avatar.try(:content_type)
  end

  def purged_keys
    keys = [surrogate_key]
    keys << avatar.surrogate_key if avatar
    keys.compact!
    keys
  end

  def surrogate_key
    owner && owner.avatar_list.surrogate_key
  end

  def can_update?
    owner && updater && owner.avatar_editable_by?(updater)
  rescue NameError # raised when owner_type is not a class
    false
  end

  def can_update
    return if can_update?
    errors.add(:updater_id, "#{updater.try(:login) || :nil} does not have access to change #{owner.try(:to_s) || :nil}'s avatar.")
  end

  def avatar_storage_blob
    if !GitHub.storage_cluster_enabled?
      nil
    else
      avatar.storage_blob || raise(GitHub::DataQualityError.new(avatar, :storage_blob))
    end
  end

  private

  def instrument_update
    return if avatar.nil?

    owner = avatar.owner

    payload = { actor: updater, owner: owner, type: avatar.owner.class.name }

    payload[audit_log_owner_key(owner)] = owner

    instrument :update, payload

    GlobalInstrumenter.instrument("profile_picture.update", {
      actor: updater,
      owner: avatar.owner,
      avatar: avatar,
    })
  end

  def event_prefix
    "profile_picture"
  end

  # When destroying an entity's Primary Avatar, this method will be called to destroy the current avatar, and
  # the previous if it exists. Only deletes avatars owned by a User entity.
  def destroy_avatars
    Avatar.find_by(id: avatar_id).try(:destroy)
    Avatar.find_by(id: previous_avatar_id).try(:destroy)
  end

  # Include this on models that act as avatar owners
  module Model
    def self.included(model)
      # Default including_deleted scope that is overridden by models as needed, such as:
      #
      # scope :including_deleted, -> { unscope(where: :deleted_at) }
      model.scope :including_deleted, -> { scoped }

      model.has_many :avatars,
        -> { order("id DESC") },
        as: :owner,
        dependent: :destroy
    end

    def all_avatars
      avs = avatars.limit(30).to_a

      if primary = primary_avatar
        # find the Avatar matching the PrimaryAvatar record
        if primary_avatar = avs.detect { |a| a.id == primary.avatar_id }
          avs.delete(primary_avatar)
        # if it's not in the batch of avatars returned, select it
        else
          primary_avatar = primary.avatar
        end
        return [primary_avatar, avs]
      end

      [nil, avs]
    end

    def can_be_avatar_owner?
      true
    end

    def primary_avatar
      return @primary_avatar if defined?(@primary_avatar)

      @primary_avatar = async_primary_avatar.sync
    end

    def primary_avatar=(avatar)
      @primary_avatar = avatar
    end

    def async_primary_avatar
      return Promise.resolve(@primary_avatar) if defined?(@primary_avatar)

      Platform::Loaders::PrimaryAvatar.load(self).then do |primary_avatar|
        @primary_avatar = primary_avatar unless defined?(@primary_avatar)
        primary_avatar
      end
    end

    def primary_avatar?(avatar)
      avatar && primary_avatar && primary_avatar.avatar_id == avatar.id
    end

    def keep_old_avatar?
      false
    end

    def handle_previous_avatar(primary)
      return if keep_old_avatar?
      return if primary.same_as_previous?
      primary.previous_avatar.try(:destroy)
    end

    def primary_avatar_url(size = nil)
      # only load uniq avatar hash if `@primary_avatar` is loaded, otherwise
      # it's a potential n+1 query issue.
      uniq = @primary_avatar.try(:unique_signature)
      PrimaryAvatar.url_for(primary_avatar_path, size: size, uniq: uniq, entity: self)
    end

    def static_avatar_url(size = nil)
      q = PrimaryAvatar.query_for(primary_avatar_path, size: size)
      q = PrimaryAvatar.add_token_and_entity_to_query(q, self, primary_avatar_path) if GitHub.multi_tenant_enterprise?
      q = PrimaryAvatar.add_jwt_token_to_query(q, primary_avatar_path) if PrimaryAvatar.current_actor_private_avatar_enabled?

      query_string = ""
      query_string += "?#{q.to_query}" unless q.empty?
      "#{PrimaryAvatar.alambic_avatar_url(self)}#{primary_avatar_path}#{query_string}"
    end

    def unique_avatar_url(size = nil)
      primary_avatar
      primary_avatar_url(size)
    end

    def primary_avatar_path
      raise NotImplementedError, "cannot build an avatar url for a #{self.class} owner"
    end

    def tenant_slug_for_avatar
      raise NotImplementedError, "tenant_slug_for_avatar not implemented for a #{self.class} owner"
    end
  end
end
