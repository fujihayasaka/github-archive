# typed: false
# frozen_string_literal: true

class Avatar::List
  include AssetUploadable::Purgeable

  module Model
    def avatar_list
      @avatar_list ||= Avatar::List.new(self)
    end

    def identicon_id
      @identicon_id ||= begin
                          if GitHub.fips_mode?
                            Digest::SHA256.hexdigest("#{self.class}:#{id}")
                          else
                            Digest::MD5.hexdigest("#{self.class}:#{id}") # rubocop:disable GitHub/InsecureHashAlgorithm
                          end
                        end
    end
  end

  def initialize(owner)
    @owner = owner
  end

  def avatar_template(internal: false)
    return unless primary = @owner.primary_avatar
    return if primary.avatar&.quarantined?
    primary.uri_template
  end

  # Get list of avatars for the user in priority order
  #
  # Returns an array of hashes with avatar info
  def items
    [primary_avatar_hash, identicon_hash].compact
  end

  def self.surrogate_key(owner)
    owner_type = owner.class.base_class.name.underscore

    if GitHub.fips_mode?
      "#{owner_type}/#{Digest::SHA256.hexdigest("avatar:#{owner.id}")}/avatars"
    else
      "#{owner_type}/#{Digest::SHA1.hexdigest("avatar:#{owner.id}")}/avatars" # rubocop:disable GitHub/InsecureHashAlgorithm
    end
  end

  def surrogate_key
    @surrogate_key ||= self.class.surrogate_key(@owner)
  end

  private

  def primary_avatar_hash
    primary_url = avatar_template
    return unless primary_url
    avatar_item("avatar", primary_url, nil, primary_avatar_fileservers)
  end

  def identicon_hash
    id = @owner.try(:identicon_id)
    return unless id
    avatar_item("identicon", "identicon:/#{id}.png")
  end

  def avatar_item(name, url, max_age = nil, fileservers = [])
    h = {
      name: name,
      url: url,
      max_age: max_age || 31557600,
    }

    return h if fileservers.empty?
    h.update(fileservers: fileservers)
  end

  # Get list of file servers a GitHub avatar has been replicated to
  #
  # Returns an array of strings
  def primary_avatar_fileservers
    return [] unless GitHub.storage_cluster_enabled?
    return [] unless @owner.primary_avatar
    @owner.primary_avatar.avatar_storage_blob.fileservers
  end
end
