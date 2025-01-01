# typed: false
# frozen_string_literal: true

module Storage
  module Uploadable
    extend ActiveSupport::Concern

    include AlambicPolicy
    include ClusterPolicy
    include Policy
    include S3Policy

    class DeletionError < StandardError
      def initialize(status, uploadable)
        super("Error deleting %s #%d from S3: HTTP %d" % [
          uploadable.class, uploadable.id,
          status
        ])
      end
    end

    included do
      if !respond_to?(:descends_from_active_record?)
        raise "Storage::Uploadable requires ActiveRecord"
      end
    end

    class_methods do
      # Public: Create a new Asset.
      # Overrided by AssetUploadable::ClassMethods#create_for_policy in
      # Avatar and Media::Blob.
      #
      # user       - The User that is uploading the asset.
      # attributes - Hash of Asset attributes.
      #              :name         - The String filename of the asset.
      #              :size         - The Integer size of the file.
      #              :content_type - The String content type of the file.
      #
      # Returns a saved Asset.
      def create_for_policy(user, attributes)
        new.save_for_policy(user, attributes)
      end

      def uploadable_policy_path
        @uploadable_policy_path ||= set_uploadable_policy_path(table_name)
      end

      def set_uploadable_policy_path(value)
        @uploadable_policy_path = value.to_sym
      end

      def uploadable_policy_attributes
        @uploadable_policy_attributes ||= [:name, :size, :content_type]
      end

      def add_uploadable_policy_attributes(*attrs)
        uploadable_policy_attributes.push(*attrs)
        uploadable_policy_attributes.uniq!
      end

      # Public: Sets up what content types this model accepts, mapped to file
      # extensions. Common groupings are defined in CONTENT_TYPES. See the
      # content_type methods below to see how they can be used in ActiveRecord
      # validations.
      #
      # hash - A Hash of String content type keys and String file extension
      #        values.  Example: { "image/gif" => ".gif" }
      #
      # Returns nothing.
      def set_content_types(hash)
        if CONTENT_TYPES.key?(hash)
          hash = CONTENT_TYPES[hash]
        end

        # maps content types to a Set of extensions that are valid
        @uploadable_content_type_extensions = {}
        # maps content types to the default extension
        @uploadable_extensions = {}

        hash.each do |content_type, extensions|
          extensions = Array(extensions)
          @uploadable_content_type_extensions[content_type] = Set.new(extensions)
          @uploadable_extensions[content_type] = extensions[0]
        end
      end

      # Public: Gets the extension for an asset (usually based on its content
      # type).
      #
      # asset - An Alambic::Asset (see Uploadable#alambic_asset).
      #
      # Returns a String extension.  Example: ".gif"
      def asset_extension(asset)
        extension_for_content_type(asset.content_type) || File.extname(asset.name)
      end

      # Public: Returns Set of allowed string content-types, useful for
      # validates_inclusion_of.
      def allowed_content_types
        return [] unless @uploadable_extensions.present?
        Set.new(@uploadable_extensions.keys)
      end

      # Public: returns a user-friendly list of all of the extensions
      # that can be uploaded, useful for reporting errors on the front-end
      def user_allowed_content_extensions
        @uploadable_content_type_extensions.values.map(&:to_a).flatten.uniq.sort
      end

      # Public: Gets the extension for a content type.
      #
      # ctype - A String content type: "image/gif"
      #
      # Returns a String extension.  Example: ".gif"
      def extension_for_content_type(ctype)
        @uploadable_extensions && @uploadable_extensions[ctype]
      end

      # Public: Gets the content type for a file extension.
      #
      # ext - A String extension: ".gif"
      #
      # Returns a String content type.  Example: "image/gif"
      def content_type_for_extension(ext)
        if @uploadable_content_type_extensions
          @uploadable_content_type_extensions.each do |ctype, extensions|
            return ctype if extensions.include?(ext)
          end
          nil
        end
      end

      # Public: Gets the valid extensions for a content type.
      #
      # ctype - A String content type: "image/gif"
      #
      # Returns a Set of String extensions, or an empty Array.
      def valid_extensions_for_content_type(ctype)
        (@uploadable_content_type_extensions && @uploadable_content_type_extensions[ctype]) ||
          []
      end
    end

    # INSTANCE METHODS

    # Public: Saves the un-uploaded Asset to generate an Asset::Policy.
    #
    # uploader   - The User that is uploading the asset.
    # attributes - Hash of Asset attributes.
    #              :name         - The String filename of the asset.
    #              :size         - The Integer size of the file.
    #              :content_type - The String content type of the file.
    #
    # Returns a saved Asset.
    def save_for_policy(uploader, attributes)
      saved = false
      self.attributes = attributes
      self.uploader = uploader
      self.state = :starter
      begin
        saved = save
      rescue ActiveRecord::RecordNotUnique => e
        ## Check if the validation functions missed this due to race condition
        ## If it is still valid, raise the error
        ## Otherwise, validation functions will put errors on the object
        ## and we will return it to the caller
        if valid?
          raise e
        end
      end
      self
    ensure
      instrument(:policy) if saved
    end

    # Public: Sanitizes the given file name, and stores the original
    # temporarily. See #original_name.
    def name=(value)
      @original_name = value
      write_attribute :name, sanitize_file_name(value)
    end

    # The original filename of the uploaded asset.
    #
    # Note: Not stored any where.  Only returned on UploadPolicy creations so
    # the markdown uploader can replace the markdown snippet with the real
    # asset url.
    def original_name
      @original_name
    end

    # Public: Tracks that the upload for the Asset has completed.
    #
    # Returns nothing.
    def track_uploaded
      return true if GitHub.storage_cluster_enabled?
      self.state = :uploaded

      save.tap do |saved|
        instrument(:uploaded) if saved
      end
    end

    # Public: Determines if the given actor is allowed to upload this object.
    def upload_access_allowed?(actor)
      upload_access_grant(actor).access_allowed?
    end

    # Public: Returns an access grant for #upload_access_allowed?
    def upload_access_grant(actor)
      raise NotImplementedError
    end

    def asset_extension
      self.class.asset_extension(self)
    end

    def name_extension
      File.extname(name.to_s).downcase
    end

    def infer_content_type
      if content_type.blank?
        self.content_type = self.class.content_type_for_extension(name_extension)
      end
    end

    def extension_matches_content_type
      ctype_ext = self.class.valid_extensions_for_content_type(content_type.to_s)
      if !ctype_ext.include?(name_extension)
        if FeatureFlag.vexi.enabled_or_raise?(:include_content_type_and_extension_in_uploadable_validation) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
          errors.add :name, "has a file extension that does not match the content type: #{name_extension} != #{content_type}"
        else
          errors.add :name, "has a file extension that does not match the content type"
        end
      end
    end

    # Internal: Sets this model's guid.  Usually called before being created.
    def set_guid
      self.created_at = Time.now
      self.guid ||= SecureRandom.uuid
    end

    def storage_ensure_inner_asset
      return unless asset = GitHub.storage_cluster_enabled? ? storage_ensure_blob : storage_ensure_asset

      if new_record?
        self.oid = asset.oid if respond_to?(:oid)
        self.size = asset.size if respond_to?(:size)
      else
        errors.add(:oid, "does not match #{asset.class}") if respond_to?(:oid) && oid != asset.oid
        errors.add(:size, "does not match #{asset.class}") if respond_to?(:size) && size != asset.size
      end
    end

    # In Gigabytes
    MAX_ASSET_SIZE = 5.gigabytes
    MAX_MULTIPART_ASSET_SIZE = 40.gigabytes
    MAX_INCREASED_MULTIPART_ASSET_SIZE = 80.gigabytes
    GHES_MULTIPART_ASSET_SIZE = 90.gigabytes
    MAX_LOCAL_MIGRATION_ASSET_SIZE = 50.gigabytes
    VALID_SIZE_RANGE = (1..MAX_ASSET_SIZE).freeze
    VALID_MULTIPART_SIZE_RANGE = (1..MAX_MULTIPART_ASSET_SIZE).freeze
    MAX_VALID_INCREASED_MULTIPART_SIZE_RANGE = (1..MAX_INCREASED_MULTIPART_ASSET_SIZE).freeze
    VALID_GHES_MULTIPART_SIZE_RANGE = (1..GHES_MULTIPART_ASSET_SIZE).freeze
    VALID_LOCAL_MIGRATION_ASSET_SIZE_RANGE = (1..MAX_LOCAL_MIGRATION_ASSET_SIZE).freeze

    # Public: Determines if the asset is within max allowable size.
    #         S3 limit w/o multipart upload is 5GB
    #         S3 limit w/ multipart upload is 40GB (90GB in GHES)
    #         ClusterPolicy limit is 50GB for MigrationFiles and 5GB for all other asset types
    def storage_ensure_asset_size
      unless storage_asset_size_range.include?(size)
        errors.add(:size, "must be less than #{human_friendly_size(storage_asset_size_range.max)} and greater than zero bytes")
      end
    end

    def storage_asset_size_range
      if is_multipart?
        VALID_MULTIPART_SIZE_RANGE
      else
        VALID_SIZE_RANGE
      end
    end

    def human_friendly_size(size)
      ActiveSupport::NumberHelper.number_to_human_size size
    end

    # Internal: Checks to see if asset is a multipart object.
    def is_multipart?
      self.respond_to?(:supports_multi_part_upload) && self.supports_multi_part_upload
    end

    # Validates this model has 1 asset in Production
    def storage_ensure_asset
      # no-op for all models except Avatar and Media::Blob
      # See AssetUploadable#storage_ensure_asset
    end

    # Validates this model has 1 storage blob in GHE
    def storage_ensure_blob
      storage_blob || begin
        errors.add(:storage_blob_id, "is required")
        nil
      end
    end

    # Public: ActiveRecord before_destroy callback that removes the object from
    # S3 in production, or the storage cluster on enterprise
    def storage_delete_object
      do_storage_delete_object
    end

    # Public: ActiveRecord before_destroy callback that removes the object from
    # S3 in production, or the storage cluster on enterprise. Unlike storage_delete_object,
    # this won't raise an error if the object doesn't exist, even if starter? returns false.
    def storage_delete_object_if_exists
      do_storage_delete_object(always_ignore_missing: true)
    end

    # Internal: Used by storage_delete_object callbacks
    def do_storage_delete_object(always_ignore_missing: false)
      return GitHub::Storage::Destroyer.dereference(self) if GitHub.storage_cluster_enabled?
      return unless res = storage_policy.try(:delete_object) # only S3Policy

      # successful 2xx response
      return res if res.status > 199 && res.status < 300

      # 404 response expected for object that was never successfully uploaded
      return res if (starter? || always_ignore_missing) && res.status == 404

      GitHub.logger.info(
        "deletion error: #{res}",
        {
          "code.function": __method__,
          "gh.storage_uploadable.name": self
        }
      )
      raise DeletionError.new(res.status, self)
    end

    # Deprecated: ActiveRecord after_destroy callback that removes the object
    # from the storage cluster only. Favor #storage_delete_object if possible.
    def storage_remove_from_cluster
      GitHub::Storage::Destroyer.dereference(self) if GitHub.storage_cluster_enabled?
      true
    end

    # Copies #parameterize from Rails, with some specific tweaks for Uploadable:
    # * Doesn't affect string casing
    # * Using "." as the separator
    # * Preserves + and @ characters
    #
    # name - String filename to sanitize.
    #
    # Returns a String.
    def sanitize_file_name(name)
      value = ActiveSupport::Inflector.transliterate(name.to_s)

      # Stripped all non-ascii characters, provide default name.
      if value.start_with?(".")
        value = "default#{value}"
      end

      # Replace special characters with the separator
      value.gsub!(/[^a-z0-9\-_\+@]+/i, FILE_NAME_SEPARATOR)

      # No more than one of the separator in a row.
      value.gsub!(/#{FILE_NAME_SEPARATOR_RE}{2,}/, FILE_NAME_SEPARATOR)

      # Remove leading/trailing separator.
      value.gsub!(/\A#{FILE_NAME_SEPARATOR_RE}|#{FILE_NAME_SEPARATOR_RE}\z/i, "")

      # Just file extension left, add default name.
      if name.to_s != value && !value.include?(".")
        value = "default.#{value}"
      end

      value
    end

    FILE_NAME_SEPARATOR = ".".freeze
    FILE_NAME_SEPARATOR_RE = Regexp.escape(FILE_NAME_SEPARATOR)

    # No-op unless Instrumentation::Model is included
    def instrument(*args)
    end

    # Deprecated: Returns the publicly accessible String URL to the file.
    def url(actor: nil)
      storage_policy(actor: actor).download_url
    end

    def metadata_url(actor: nil)
      storage_policy(actor: actor).metadata_url
    end

    STATES = {
      starter: 0,
      uploaded: 1,
      deleted: 2,
      multipart_upload_started: 3,
      multipart_upload_list_parts: 4,
      multipart_upload_completed: 5,
    }

    # Separate from IMAGE_CONTENT_TYPES because SVGs aren't yet supported everwhere
    # that images are, e.g. repository images.
    SVG_CONTENT_TYPE = {
      "image/svg+xml" => ".svg",
    }

    IMAGE_CONTENT_TYPES = {
      "image/gif"  => ".gif",
      "image/jpeg" => %w(.jpg .jpeg),
      "image/png"  => ".png",
    }

    # Although most browsers codify .mov files as `video/quicktime`, certain Android
    # browsers codify .mov files as `video/mp4`. To support video upload on Android
    # devices, we needed to support either .mp4 or .mov extensions as `video/mp4`.
    VIDEO_CONTENT_TYPES = {
      "video/quicktime" => ".mov",
      "video/mp4" => %w(.mp4 .mov),
      "video/webm" => ".webm",
    }

    CONTENT_TYPES = {
      images: IMAGE_CONTENT_TYPES,
      media: SVG_CONTENT_TYPE.merge(IMAGE_CONTENT_TYPES.merge(VIDEO_CONTENT_TYPES)),
    }
  end
end
