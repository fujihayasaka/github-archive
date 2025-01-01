# typed: true
# frozen_string_literal: true
require "nokogiri"

module Elastomer::Adapters

  # The Release adapter is used to transform a release ActiveRecord
  # object into a Hash document that can be indexed in ElasticSearch.
  #
  class Release < ::Elastomer::Adapter

    # ES request is limited to 25 Mb, so we limit body to 24 Mb, there's not much more data in a release
    DEFAULT_MAX_BODY_BYTESIZE = 24.megabytes

    # The largest possible int value (which is way larger than what we'd expect in a version number)
    # This will ignore versions like 202110121001, which won't have major/minor/patch numbers,
    # but that will fallback to alphabetic "tag_name" ordering.
    MAX_VERSION_NUMBER = 1_073_741_824

    def initialize(*args)
      super(*T.unsafe(args))
      @max_body_bytesize = options.fetch(:max_body_bytesize, DEFAULT_MAX_BODY_BYTESIZE)
    end

    # Public: Returns the name of the Index class responsible for storing the
    # generated documents.
    def self.index_name
      "Releases"
    end

    def self.mysql_cluster
      ::Release.cluster_name
    end

    # Public: Accessor for the data model instance. If the `document_id` does
    # not map to any row in the database, then `nil` is returned.
    #
    # Returns the data model instance.
    #
    def model
      @model ||= ::Release.find_by(id: document_id)
    end
    alias :release :model

    # Public: Construct a document suitable for indexing in ElasticSearch and
    # return it as a Hash.
    #
    # Returns the ElasticSearch document as a Hash.
    #
    def to_hash
      if model.nil?
        raise Elastomer::ModelMissing, "The data model has not been set, or the document ID does not exist in the database."
      end

      return @hash if defined? @hash
      @hash = nil

      return unless release.is_searchable?

      major, minor, patch = parse_semver release.exposed_tag_name

      sanitized_body = ::Search.clean_and_sanitize(release.body)

      # truncate consumes memory even if no truncation, so check first if necessary
      if sanitized_body.bytesize > @max_body_bytesize
        sanitized_body = sanitized_body.truncate(@max_body_bytesize, separator: " ", omission: "")
      end

      @hash = {
        _id: document_id.to_s,
        _type: document_type,
        tag_name: release.exposed_tag_name,
        version_major: major,
        version_minor: minor,
        version_patch: patch,
        name: release.name,
        body: sanitized_body,
        draft: release.draft?,
        prerelease: release.prerelease?,
        repo_id: release.repository_id,
        author_id: release.author_id,
        created_at: release.created_at,
        created_day: release.created_at.utc.midnight,
        updated_at: release.updated_at,
        published_at: release.published_at,
      }
    end

    def parse_semver(version)
      return unless version.present?

      if version[0] == "v"
        version = version[1..]
      end

      semver_parts = []
      major_raw, minor_raw, patch_raw = version.split(".")

      major = major_raw.to_i
      if major.to_s == major_raw
        semver_parts << major
        minor = minor_raw.to_i
        if minor.to_s == minor_raw
          semver_parts << minor

          # The patch version doesn't necessarily have to be an integer to accomodate cases such as 3.1.3-alpha - this should return 3 as the patch version
          semver_parts << patch_raw.to_i if patch_raw.present?
        end
      end

      semver_parts.map { |n| n <= MAX_VERSION_NUMBER ? n : nil }
    end
  end
end
