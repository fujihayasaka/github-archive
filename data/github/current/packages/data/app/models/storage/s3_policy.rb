# typed: false
# frozen_string_literal: true

require "s3_sign"

module Storage
  # This policy defines how files are stored and accessed using S3 directly.
  class S3Policy < Storage::Policy
    def delete_object
      return if Rails.env.test? && self.class.faraday.nil?
      path = @uploadable.storage_s3_key(self)
      sign = s3_sign.header(s3_credentials, "DELETE", path, nil)
      self.class.faraday.delete do |req|
        req.url("#{upload_url}/#{path}")
        sign.to_hash.each do |key, value|
          req.headers[key] = value
        end
      end
    end

    def using_cdn?(uploadable)
      return false if GitHub.multi_tenant_enterprise?
      uploadable.respond_to?(:storage_fastly_acceleration_bucket) && uploadable.storage_fastly_acceleration_bucket != nil
    end

    def download_url(_ = nil, expiration: nil)
      now = Time.now
      url, signer = retrieve_url_and_signer(expiration: expiration)
      if using_cdn?(@uploadable)
        url = @uploadable.cdn_url(url)
      end
      url
    ensure
      stats_timing(:download, start: now) if now
    end

    def metadata_url(_ = nil, use_cdn: true)
      now = Time.now
      url, signer = retrieve_url_and_signer("HEAD")
      if using_cdn?(@uploadable) && use_cdn
        url = @uploadable.cdn_url(url)
      end
      url
    ensure
      stats_timing(:metadata, start: now) if now
    end

    def download_link
      now = Time.now
      url, signer = retrieve_url_and_signer
      href_url = using_cdn?(@uploadable) ? @uploadable.cdn_url(download_url) : download_url
      h = { href: href_url }
      if signer
        h[:expires_at] = signer.expires_at.xmlschema
        h[:expires_in] = signer.expires.to_i
      end

      h
    ensure
      stats_timing(:download, start: now) if now
    end

    def multi_part_upload_url_headers(state)
      sign = {}
      path = @uploadable.storage_s3_key(self)
      case state
      when "starter"
        sign = s3_sign.header(s3_credentials, "POST", path, s3_sign::EMPTY_BODY_HASH)
        sign.query[:uploads] = ""

      when "multipart_upload_started"
        sign = s3_sign.header(s3_credentials, "PUT", path, @uploadable.part_sha)
        sign.query[:partNumber] = @uploadable.part_number
        sign.query[:uploadId] = @uploadable.multi_part_upload_id

      when "multipart_upload_list_parts"
        sign = s3_sign.header(s3_credentials, "GET", path, s3_sign::EMPTY_BODY_HASH)
        sign.query[:uploadId] = @uploadable.multi_part_upload_id

      when "multipart_upload_completed"
        sign = s3_sign.header(s3_credentials, "POST", path, @uploadable.part_sha)
        sign.query[:uploadId] = @uploadable.multi_part_upload_id

      end

      { url: sign.location, headers: sign.to_hash }
    end

    def upload_url
      if b = @uploadable.storage_s3_bucket
        "https://#{b}.s3.amazonaws.com"
      else
        GitHub.s3_asset_bucket_host
      end
    end

    def lfs_upload_link
      sign = s3_sign.header(s3_credentials, "PUT", @uploadable.storage_s3_key(self), @uploadable.oid)
      add_signed_query_params(sign)
      {
        href: sign.location,
        header: sign.to_hash,
        expires_at: sign.expires_at.xmlschema,
        expires_in: sign.expires.to_i,
      }
    end

    def acl
      case access = @uploadable.storage_s3_access
      when :private then "private"
      when :public then "public-read"
      else
        GitHub.logger.info(
          "Unknown storage access",
          {
            "code.function": __method__,
            "gh.storage_policy.policy": "S3Policy",
            "gh.storage_policy.access": access.inspect,
            "gh.storage_policy.uploadable": @uploadable.inspect
          }
        )
        raise ArgumentError, "Unknown storage access for #{@uploadable.class} #{@uploadable.id}"
      end
    end

    protected

    def retrieve_url_and_signer(method = "GET", expiration: nil)
      if @uploadable.storage_s3_access == :public
        return ["#{upload_url}/#{@uploadable.storage_s3_key(self)}", nil]
      end

      expiration = @uploadable.storage_download_expiration.to_i if expiration.nil?
      sign = s3_sign.query(s3_credentials, method, @uploadable.storage_s3_key(self), expiration, nil, @uploadable.storage_s3_region)
      add_signed_query_params(sign) if @uploadable.is_a?(Media::Blob)
      @uploadable.storage_s3_download_query(sign.query)
      [sign.location, sign]
    end

    def add_signed_query_params(sign)
      sign.query[:actor_id] = @actor ? @actor.id : 0
      sign.query[:repo_id] = @repository.is_a?(Repository) ? @repository.id : 0
      sign.query[:key_id] = @key.is_a?(PublicKey) ? @key.id : 0
      if GitHub.multi_tenant_enterprise?
        owner = @repository.is_a?(Repository) ? @repository.network_owner : nil
        if owner.nil?
          sign.query[:org_id] = 0
          sign.query[:cust_id] = 0
        else
          if owner.delegate_billing_to_business?
            customer_id = owner.business.customer_id
          else
            customer_id = owner.customer&.id
            customer_id = 0 if customer_id.nil?
          end
          sign.query[:org_id] = owner.is_a?(Organization) ? owner.id : 0
          sign.query[:cust_id] = customer_id
        end
      end
    end

    def s3_sign
      S3Sign
    end

    private

    def upload_form
      sign = s3_sign.upload(s3_credentials)
      object_key = @uploadable.storage_s3_key(self)
      upload_policy = build_policy(object_key, sign)
      json_policy = GitHub::JSON.encode(upload_policy)
      sign.encoded_policy = Base64.encode64(json_policy).gsub("\n", "")

      form = {
        key: object_key,
        acl: acl,
        policy: sign.encoded_policy,
      }.merge(sign.form)

      each_s3_header do |key, value|
        form[key] = value
      end

      form
    end

    def same_origin_upload?
      false
    end

    # Generate the policy document to send to S3 in the file upload form. This
    # allows users to upload files to our bucket. Verifies that the file they're
    # actually uploading matches the content type and file size they claim to be
    # saving to the bucket.
    #
    # The keys in this document must match the fields in the file upload  form
    # exactly. No additional form fields may be included in the post.
    #
    # Returns a hash.
    def build_policy(object_key, sign)
      conditions = [
        { bucket: @uploadable.storage_s3_bucket },
        { key: object_key },
        { acl: acl },
        ["content-length-range", @uploadable.size, @uploadable.size],
      ] + sign.policy

      each_s3_header do |key, value|
        conditions << { key => value }
      end

      expiration = @uploadable.storage_upload_expiration
      {
        expiration: expiration.from_now.utc.iso8601,
        conditions: conditions,
      }
    end

    # Returns a Hash of custom headers applied to the S3 file.
    def each_s3_header
      @uploadable.storage_s3_upload_header.each do |key, value|
        next unless valid_s3_header_key?(key)
        yield key, value
      end
    end

    def valid_s3_header_key?(key)
      S3_REST_HEADERS.include?(key) || key =~ /^x-amz-meta-/
    end

    S3_REST_HEADERS = Set.new(%w(
      Cache-Control
      Content-Type
      Content-Disposition
      Content-Encoding
      Expires))

    def s3_credentials
      {
        bucket: @uploadable.storage_s3_bucket,
        key: @uploadable.storage_s3_access_key,
        secret: @uploadable.storage_s3_secret_key,
      }
    end
  end
end
