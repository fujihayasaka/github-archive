# typed: true
# frozen_string_literal: true

class User::AvatarList
  include AssetUploadable::Purgeable

  module Model
    def avatar_list
      @avatar_list ||= User::AvatarList.new(self)
    end
  end

  DEFAULT_IMAGE = "gravatar-user-420"

  def self.with_gravatar_id(gid)
    new(User.new, gravatar_id: gid)
  end

  def self.anonymous_user(login)
    User.new(login: login)
  end

  def initialize(user, gravatar_id: nil)
    @user = user
    @gravatar_id = gravatar_id
  end

  def gravatar_url(size = 30, default_image = nil)
    fallback = identicons_url || fallback_url(default_image)
    return fallback unless has_gravatar?
    self.class.gravatar_url_for(@user, size, default: fallback, gravatar_id: @gravatar_id)
  end

  def avatar_template(internal: false)
    return unless primary = @user.primary_avatar
    return if primary.avatar.nil? # This should only happen if avatars were directly deleted from the database
    return if primary.avatar.quarantined?
    primary.uri_template
  end

  def gravatar_uri_template
    return unless gid = gravatar_id
    "#{GitHub.gravatar_url(nil)}/avatar/#{gid}?r=x&d=404&s={size}"
  end

  def identicons_url
    return unless id = identicon_id

    # Enterprise can switch the identicons host to .com and that means the url
    # changes to the other form, so only use /identicons when the host matches
    # the instance.
    if GitHub.enterprise? && GitHub.identicons_host == GitHub.url
      return "#{GitHub.identicons_host}/identicons/#{id}.png"
    end

    "#{GitHub.identicons_host}/#{id}.png"
  end

  def fallback_url(default_image = nil)
    self.class.default_image_url(default_image)
  end

  # Get list of avatars for the user in priority order
  #
  # Returns an array of hashes with avatar info
  def items
    list = []

    if primary_url = avatar_template
      list << avatar_item("avatar", primary_url, nil, primary_avatar_fileservers)
    elsif url = gravatar_uri_template
      list << avatar_item("gravatar", url, 3600) if url
    end

    if id = identicon_id
      list << avatar_item("identicon", "identicon:/#{id}.png")
    end

    list
  end

  def self.default_image_url(default_image = nil)
    "#{GitHub.asset_host_url}/images/gravatars/#{default_image || DEFAULT_IMAGE}.png"
  end

  def self.gravatar_url_for(email, size = 30, default: nil, gravatar_id: nil)
    if !GitHub.gravatar_enabled?
      return default_image_url(default)
    end

    default ||= DEFAULT_IMAGE

    gid = if gravatar_id
      gravatar_id
    elsif email.respond_to?(:gravatar_id)
      email.gravatar_id
    else
      GitHub.generate_gravatar_id(email.to_s.downcase)
    end

    default = default_image_url(default) unless default =~ /\A(https?\:\/)?\//
    query = { d: default, r: "g" }
    query[:s] = size.to_i if size.to_i > 0

    "#{GitHub.gravatar_url(gid)}/avatar/#{gid}?#{query.to_query}"
  end

  def self.surrogate_key(user)
    if GitHub.fips_mode?
      "user/#{Digest::SHA256.hexdigest("avatar:#{user.id || user.email}")}/avatars"
    else
      "user/#{Digest::SHA1.hexdigest("avatar:#{user.id || user.email}")}/avatars" # rubocop:disable GitHub/InsecureHashAlgorithm
    end
  end

  def surrogate_key
    @surrogate_key ||= self.class.surrogate_key(@user)
  end

  private

  def has_gravatar?
    gravatar_id.present?
  end

  def gravatar_id
    return nil unless GitHub.gravatar_enabled?
    @gravatar_id || @user.gravatar_id
  end

  def identicon_id
    @user.identicon_id if @user.display_login.present? || @user.email.present?
  end

  def avatar_item(name, url, max_age = nil, fileservers = [])
    h = {
      name: name,
      url: url,
      max_age: max_age || 31557600,
    }

    if !fileservers.empty?
      h[:fileservers] = fileservers
    end
    h
  end

  # Get list of file servers a GitHub avatar has been replicated to
  #
  # Returns an array of strings
  def primary_avatar_fileservers
    if !GitHub.storage_cluster_enabled? || !@user.primary_avatar
      return []
    end

    @user.primary_avatar.avatar_storage_blob.fileservers
  end
end
