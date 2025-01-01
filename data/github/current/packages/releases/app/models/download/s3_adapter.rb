# typed: true
# frozen_string_literal: true

class Download::S3Adapter
  def self.move(old_adapter, new_adapter)
    move_paths old_adapter.path, new_adapter.path
  end

  # Moves download file from its old path to its new path
  #
  # Will return early if file has been moved already or deleted
  #
  # Returns nothing.
  def self.move_paths(old_path, new_path)
    client = GitHub.s3_primary_client
    bucket = GitHub.s3_environment_config[:bucket_name]

    unless object_exists?(old_path)
      Failbot.report(StandardError.new("Old file not found"))
      return
    end

    if object_exists?(new_path)
      Failbot.report(StandardError.new("New file already exists"))
      return
    end

    client.copy_object(
      copy_source: "/#{bucket}/#{old_path}",
      bucket: bucket,
      key: new_path,
    )

    old_acl = client.get_object_acl(
      bucket: bucket,
      key: old_path,
    )

    client.put_object_acl(
      bucket: bucket,
      key: new_path,
      access_control_policy: {
        grants: encode_grants(old_acl.grants),
        owner: {
          id: old_acl.owner.id,
          display_name: old_acl.owner.display_name,
        },
      },
    )

    client.delete_object(
      bucket: bucket,
      key: old_path,
    ) if object_exists?(new_path)
  end

  attr_reader :download
  attr_accessor :public, :repo_owner, :repo_name, :bucket,
    :secret_access_key, :access_key

  def initialize(download, is_public = nil, repo_owner = nil, repo_name = nil)
    @client = GitHub.s3_primary_client
    @public = is_public || download.repository.public?
    @repo_owner = repo_owner || download.repository.owner.to_s
    @repo_name = repo_name || download.repository.to_s

    @bucket = GitHub.s3_environment_config[:bucket_name]
    @secret_access_key = GitHub.s3_environment_config[:secret_access_key]
    @access_key = GitHub.s3_environment_config[:access_key_id]

    @download = download
  end

  def dup
    self.class.new(@download, @public, @repo_owner, @repo_name)
  end

  def public?
    !!@public
  end

  def repo_path
    @repo_path ||= [@repo_owner, @repo_name].join("/")
  end

  def repo_permalink
    @repo_permalink ||= [GitHub.url, @repo_owner, @repo_name].join("/")
  end

  def path
    @path ||= File.join("downloads", repo_path, @download.name)
  end

  # Constructs a URL to download a file.
  #
  # Returns a URL String.
  def url
    Aws::S3::Object.new(@bucket, path, client: @client).
      presigned_url(:get, expires_in: 5.minutes.to_i)
  end

  # Public: Checks to see if the file exists on S3.
  #
  # Returns true or false.
  def file_exists?
    self.class.object_exists?(path)
  end

  # Removes the file from S3 permanently.
  #
  # Returns nothing.
  def delete_file
    @client.delete_object(bucket: @bucket, key: path)
  end

  def self.object_exists?(key)
    Aws::S3::Object.new(GitHub.s3_environment_config[:bucket_name], key,
      client: GitHub.s3_primary_client
    ).exists?
  end

  def self.encode_grants(grants)
    grants.map do |g|
      {
        permission: g.permission,
        grantee: {
          display_name: g.grantee.display_name,
          id: g.grantee.id,
          type: g.grantee.type,
          uri: g.grantee.uri,
        },
      }
    end
  end
end
