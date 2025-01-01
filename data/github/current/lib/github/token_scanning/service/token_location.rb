# typed: true
# frozen_string_literal: true

# Wrapper class for the protobuf token location class returned from the service.
#
# Implements the same methods as `TokenScanResultLocation` so that is can be
# use interchangeably in the views.
class GitHub::TokenScanning::Service::TokenLocation
  attr_reader :location, :repository

  delegate :blob_oid, :commit_oid, :end_column, :end_line, :start_column, :start_line, :exclude_by_path, :start_line, to: :location

  def initialize(location, repository)
    @location = location
    @repository = repository
  end

  def created_at
    location.created_at.to_time
  end

  def found_in_archive?
    start_line.zero? && end_line.zero?
  end

  def raw_path
    location.path
  end

  def path
    location.path.dup.force_encoding(::Encoding::UTF_8).scrub!
  end

  def blob
    return @blob if defined? @blob

    case location.content_type
    when :REPOSITORY_BLOB
      raw_blob = repository.rpc.read_blobs([blob_oid]).first
      @blob = TreeEntry.new(repository, raw_blob.merge("path" => path))
    when :WIKI_BLOB
      if !repository.unsullied_wiki.present?
        @blob = nil
      end
      raw_blob = repository.unsullied_wiki.rpc.read_blobs([blob_oid]).first
      @blob = TreeEntry.new(repository.unsullied_wiki, raw_blob.merge("path" => path))
    else
      @blob = nil
    end
  rescue GitRPC::ObjectMissing, GitRPC::InvalidObject
    @blob = nil
  end

  def normalized_start_column
    start_column + 1
  end

  def normalized_end_column
    end_column + 1
  end

  def content_type
    location.content_type
  end

  def content_id
    location.content_id
  end

  def content_number
    location.content_number
  end
end
