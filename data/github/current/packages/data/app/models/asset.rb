# typed: true
# frozen_string_literal: true

# Tracks the metadata for the content addressable asset store in the Alambic
# service.  Each Asset stores the basic immutable metadata.  Some of it is
# always set (size, sha1, md5, and sha-256).  Other attributes may be specific
# to a certain file type (image width and height).  An Asset may be shared
# between multiple uploadable models through the Asset::Reference association.
class Asset < ApplicationRecord::Domain::Assets # rubocop:todo GitHub/DatabaseModelsShouldHaveTests
  extend T::Sig

  # Defers #size to Asset in models that need it just for validations.
  module SizeHelper
    extend T::Sig
    extend T::Helpers

    abstract!

    def size
      asset ? T.must(asset).size : 0
    end

    def size_before_type_cast
      asset ? T.must(asset).size_before_type_cast : 0
    end

    sig { abstract.returns(T.nilable(Asset)) }
    def asset; end
  end

  ACCEPTED_METADATA = [:width, :height]

  has_many :archives, class_name: "Asset::Archive"
  has_many :references, class_name: "Asset::Reference"

  validates_presence_of :oid, :size
  validates_numericality_of :size, greater_than: -1
  validates_length_of :oid, is: 64

  # All Assets are stored in Alambic according to the sha-256 hash of the
  # contents.
  validates_uniqueness_of :oid, case_sensitive: false
  validate :meta_data_is_immutable

  # Public: Uploads a feature with the given oid and meta data, and associate it
  # with an asset.
  sig do
    params(
      uploadable: T.nilable(AssetUploadable),
      oid: String,
      meta: T::Hash[Symbol, T.untyped]
    ).
    returns(T.nilable(AssetUploadable))
  end
  def self.upload(uploadable, oid, meta)
    transaction do
      asset = find_or_init_with_meta(meta.merge(oid: oid))
      asset_uploadable = uploadable ? uploadable : T.cast((yield asset), AssetUploadable)
      asset.reference!(asset_uploadable)
      asset_uploadable.after_upload(meta)
      uploadable = asset_uploadable
    end

    uploadable
  end

  def self.store(uploadable, meta = nil)
    meta ||= {}
    meta[:oid] ||= uploadable.oid
    meta[:size] ||= uploadable.size
    asset = where(oid: uploadable.oid).first_or_initialize(oid: uploadable.oid)

    transaction do
      asset.update_meta(meta)
      yield asset if block_given?
      asset.reference!(uploadable)
    end

    asset
  end

  # Public: References the given uploadable object to this Asset.  Any
  # Asset::Archive references are deleted too.
  def reference!(uploadable)
    ActiveRecord::Base.connected_to(role: :writing) do
      bindings = {
        asset_id: id,
        uploadable_id: uploadable_id(uploadable),
        uploadable_type: uploadable.class.base_class.name,
        created_at: current_time_from_proper_timezone,
      }

      transaction do
        Asset::Reference.connection.insert(Arel.sql(<<-SQL, **bindings))
          INSERT INTO asset_references
            (asset_id, uploadable_id, uploadable_type, created_at)
          VALUES
            (:asset_id, :uploadable_id, :uploadable_type, :created_at)
          ON DUPLICATE KEY UPDATE
            asset_id = asset_id
        SQL

        unarchive!(uploadable)
      end
    end
  end

  # Public: Remove the reference of the given uploadable from this Asset.  If
  # there are no more references, create an Asset::Archive reference so the Asset
  # can be purged later.
  def dereference!(uploadable)
    ref = references.where(
      uploadable_id: uploadable_id(uploadable),
      uploadable_type: uploadable.class.base_class.name,
    ).first

    transaction do
      ref.destroy if ref
      archive!(uploadable) if uploadable.archive?(self)
    end
  end

  def uploadable_id(uploadable)
    uploadable_id = uploadable&.id
    raise GitHub::DataQualityError.new(self, :uploadable_id) if uploadable_id.nil?
    uploadable_id
  end

  # Internal: Creates an Asset::Archive reference for this Asset, scheduling it to
  # be purged later (if no other references are created).
  #
  # Note: NOT run in a transaction.  This should only be called from the
  # transaction inside #dereference!
  def archive!(uploadable)
    ActiveRecord::Base.connected_to(role: :writing) do
      bindings = {
        asset_id: id,
        path_prefix: uploadable.alambic_path_prefix,
        created_at: current_time_from_proper_timezone,
      }

      Asset::Archive.connection.insert(Arel.sql(<<-SQL, **bindings))
        INSERT INTO asset_archives
          (asset_id, path_prefix, created_at)
        VALUES
          (:asset_id, :path_prefix, :created_at)
        ON DUPLICATE KEY UPDATE
          created_at = :created_at
      SQL

      reference! archives.order("id DESC").first
    end
  end

  # Internal: Remove any Asset::Archive references for this Asset.
  #
  # Note: NOT run in a transaction.  This should only be called from the
  # transaction inside #reference!
  def unarchive!(uploadable)
    return if uploadable.is_a?(Asset::Archive)
    return unless arc = archives.where(path_prefix: uploadable.alambic_path_prefix).first
    dereference!(arc)
    arc.destroy
  end

  # Public: Remove any Asset::Archive references, and delete this asset if it
  # has no other references.
  def purge!(archives)
    archives = archives.select { |arc| arc.asset_id == id }
    return false if archives.blank?

    ActiveRecord::Base.connected_to(role: :writing) do
      transaction do
        Asset::Reference.purge(self, archives)
        Asset::Archive.where(id: archives).delete_all

        if references.count == 0
          destroy
          true
        else
          false
        end
      end
    end
  end

  def image_dimensions?
    width.to_i + height.to_i > 0
  end

  def self.find_or_init_with_meta(meta)
    oid = meta[:oid]

    ActiveRecord::Base.connected_to(role: :writing) do
      bindings = {
        oid: oid,
        size: meta[:size].to_i,
        width: meta[:width].to_i,
        height: meta[:height].to_i,
        created_at: new.send(:current_time_from_proper_timezone),
      }

      transaction do
        self.connection.insert(Arel.sql(<<-SQL, **bindings))
          INSERT INTO assets
            (oid, size, width, height, created_at)
          VALUES
            (:oid, :size, :width, :height, :created_at)
          ON DUPLICATE KEY UPDATE
            oid = oid
        SQL
      end
    end

    find_by(oid: oid)
  end

  # Public: Saves the meta data.  Asset meta data should be fully set during
  # creation, and never updated.
  #
  # meta - Hash of the asset's meta data.
  #
  # Returns nothing.
  def update_meta(meta)
    if set_meta(meta)
      raise ActiveRecord::RecordInvalid, self if invalid?

      ActiveRecord::Base.connected_to(role: :writing) do
        bindings = {
          oid: meta[:oid] || oid,
          size: (meta[:size] || size).to_i,
          width: (meta[:width] || width).to_i,
          height: (meta[:height] || height).to_i,
          created_at: GitHub::SQL::ArelLiterals::NOW,
        }

        transaction do
          self.class.connection.insert(Arel.sql(<<-SQL, **bindings))
            INSERT INTO assets
              (oid, size, width, height, created_at)
            VALUES
              (:oid, :size, :width, :height, :created_at)
            ON DUPLICATE KEY UPDATE
              oid = oid
          SQL

          # Since we're not using AR's save, if we're acting on an
          # unsaved object, it will not have an id set. So we ask for the one
          # we just geneated by OID
          if self.id.nil?
            sql = "SELECT id FROM assets WHERE oid = :oid"
            self.id = self.class.connection.select_value(Arel.sql(sql, oid: meta[:oid] || oid))
          end
        end
      end
    end
  end

  def set_meta(meta)
    return if meta.blank?

    if size = meta[:size]
      self.size = size
    end

    self.width = meta[:width] if width.to_i.zero?
    self.height = meta[:height] if height.to_i.zero?
    changed?
  end

  def set_meta_data(meta, key)
    return unless value = meta[key]
    send("#{key}=", value)
  end

  def meta_data_is_immutable
    old, updated = size_change
    if updated && old && old != updated
      errors.add(:size, "cannot be changed")
    end
  end
end
