# typed: true
# frozen_string_literal: true

class S3Sign
  # sha-256 hash of ""
  EMPTY_BODY_HASH = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

  SIGNATURE_ALGORITHM = "AWS4-HMAC-SHA256"
  AWS_REGION = "us-east-1"

  def self.header(credentials, method, key, sha, now = Time.now.utc, region = AWS_REGION)
    Header.new(credentials, method, key, sha, 15.minutes.to_i, now, region)
  end

  def self.query(credentials, method, key, expires, now = Time.now.utc, region = AWS_REGION)
    Query.new(credentials, method, key, "", expires, now, region)
  end

  def self.upload(credentials, now = Time.now, region = AWS_REGION)
    now = now.utc.beginning_of_day
    Upload.new(credentials, "", "", "", 0, now, region)
  end

  attr_reader :query
  attr_reader :expires
  attr_reader :expires_at
  attr_reader :region

  EMPTY_BODY_VERBS = Set.new(%w(GET HEAD DELETE))

  def initialize(credentials, method, key, sha, expires, now, region, endpoint_provider = S3Provider)
    @credentials = credentials
    @verb = method
    @key = Pathname.new("/").join(key).to_s
    @sha = if EMPTY_BODY_VERBS.include?(@verb) && sha.blank?
      EMPTY_BODY_HASH
    else
      sha
    end
    @expires = expires
    @now = (now || Time.now).utc
    @expires_at = @now + @expires
    @region = if region.blank?
      AWS_REGION
    else
      region
    end
    @query = {}
    @endpoint_provider = endpoint_provider
  end

  def time
    @now.strftime("%Y%m%dT%H%M%SZ")
  end

  private

  # convert a flat hash of URI key/value pairs to an escaped string.
  def to_query(q)
    # we want them sorted in capital and alphabetical order, but the query may
    # have symbol keys.
    string_keys = {}
    q.each_key do |key|
      string_keys[key.to_s] = key
    end

    string_keys.keys.sort.map do |key|
      real_key = string_keys[key]
      "#{UrlHelper.escape_path(key)}=#{UrlHelper.escape_path(q[real_key].to_s)}"
    end.join("&")
  end

  def to_query_string(q)
    qs = to_query(q)
    qs.blank? ? qs : "?#{qs}"
  end

  def string_to_sign(request)
    "%s\n%s\n%s/%s/s3/aws4_request\n%s" % [
      SIGNATURE_ALGORITHM,
      @now.strftime("%Y%m%dT%H%M%SZ"),
      @now.strftime("%Y%m%d"),
      region,
      Digest::SHA256.hexdigest(request),
    ]
  end

  def signature(sts, now)
    kdate = OpenSSL::HMAC.digest("sha256", "AWS4#{@credentials[:secret]}", now.strftime("%Y%m%d"))
    kregion = OpenSSL::HMAC.digest("sha256", kdate, region)
    kservice = OpenSSL::HMAC.digest("sha256", kregion, "s3")
    kcreds = OpenSSL::HMAC.digest("sha256", kservice, "aws4_request")
    OpenSSL::HMAC.hexdigest("sha256", kcreds, sts)
  end

  def credential
    "%s/%s/%s/s3/aws4_request" % [@credentials[:key], @now.strftime("%Y%m%d"), region]
  end

  def s3_host_protocol
    @endpoint_provider.s3_host_protocol
  end

  def s3_host
    @endpoint_provider.s3_host(@credentials[:bucket], @region)
  end

  def s3_port
    @endpoint_provider.s3_port
  end

  def s3_url
    url = "%s://%s" % [s3_host_protocol, s3_host]
    if s3_port != nil
      url += ":%d" % s3_port
    end
    url + s3_path
  end

  def s3_path
    @endpoint_provider.s3_path(@credentials[:bucket], @key)
  end

  class Header < S3Sign
    def token
      @token ||= token_string(canonical_request)
    end

    def location
      @location ||= s3_url + to_query_string(@query)
    end

    def canonical_request
      @canonical_request ||= begin
        @query.freeze
        "%s\n%s\n%s\nhost:%s\nx-amz-content-sha256:%s\nx-amz-date:%s\n\n%s\n%s" % [
          @verb,
          s3_path,
          to_query(@query),
          s3_host,
          @sha,
          @now.strftime("%Y%m%dT%H%M%SZ"),
          "host;x-amz-content-sha256;x-amz-date",
          @sha,
        ]
      end
    end

    def to_hash
      {
        "Authorization" => token,
        "x-amz-content-sha256" => @sha,
        "x-amz-date" => time,
      }
    end

    private

    def token_string(c)
      sts = string_to_sign(c)
      sig = signature(sts, @now)
      "%s Credential=%s,SignedHeaders=%s,Signature=%s" % [
        SIGNATURE_ALGORITHM,
        credential,
        "host;x-amz-content-sha256;x-amz-date",
        sig,
      ]
    end
  end

  class Query < S3Sign
    def token
      @token ||= begin
        sts = string_to_sign(canonical_request)
        signature(sts, @now)
      end
    end

    def location
      @location ||= begin
        s3_url + to_query_string(@query.merge("X-Amz-Signature" => token))
      end
    end

    def canonical_request
      @canonical_request ||= begin
        @query.update(
          "X-Amz-Algorithm" => SIGNATURE_ALGORITHM,
          "X-Amz-Credential" => credential,
          "X-Amz-Date" => @now.strftime("%Y%m%dT%H%M%SZ"),
          "X-Amz-Expires" => @expires,
          "X-Amz-SignedHeaders" => "host",
        )
        @query.freeze

        host = s3_port ? "#{s3_host}:#{s3_port}" : s3_host
        "%s\n%s\n%s\nhost:%s\n\nhost\nUNSIGNED-PAYLOAD" % [
          @verb,
          s3_path,
          to_query(@query),
          host,
        ]
      end
    end
  end

  # Based on https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-HTTPPOSTForms.html
  class Upload < S3Sign
    attr_accessor :encoded_policy

    def policy
      [
        { "x-amz-credential" => credential },
        { "x-amz-algorithm" => SIGNATURE_ALGORITHM },
        { "x-amz-date" => time },
      ]
    end

    def form
      {
        "X-Amz-Algorithm" => SIGNATURE_ALGORITHM,
        "X-Amz-Credential" => credential,
        "X-Amz-Date" => time,
        "X-Amz-Signature" => signature(encoded_policy, @now),
      }
    end
  end

  class S3Provider
    def self.s3_host_protocol
      "https"
    end

    def self.s3_host(bucket_with_path, region = AWS_REGION)
      parts = bucket_with_path.split("/")
      # any region that includes "gov" is not supporting global s3 endpoints
      if region.include?("gov")
        "%s.s3.%s.amazonaws.com" % [parts[0], region]
      else
        "%s.s3.amazonaws.com" % [parts[0]]
      end
    end

    def self.s3_port
      nil
    end

    def self.s3_path(bucket, key)
      parts = bucket.split("/")
      root = ""
      if parts.size > 1
        root = parts[1...-1].join("/")
      end

      Pathname.new("/").join(root, key).to_s
    end
  end

  class MemoryAlphaProvider
    def self.s3_host_protocol
      GitHub.memory_alpha_scheme
    end

    def self.s3_host(bucket_with_path, region = AWS_REGION)
      GitHub.memory_alpha_host
    end

    def self.s3_port
      GitHub.memory_alpha_port
    end

    def self.s3_path(bucket, key)
      parts = bucket.split("/")
      "/%s%s" % [parts[0], key]
    end
  end

  class LfsProvider < MemoryAlphaProvider
    def self.s3_host_protocol
      GitHub.lfs_storage_host_protocol
    end

    def self.s3_host(bucket_with_path, region = AWS_REGION)
      GitHub.lfs_storage_host
    end
  end
end

class MemoryAlphaSign < S3Sign
  def self.header(credentials, method, key, sha, now = Time.now.utc, region = AWS_REGION)
    Header.new(credentials, method, key, sha, 15.minutes.to_i, now, region, MemoryAlphaProvider)
  end

  def self.query(credentials, method, key, expires, now = Time.now.utc, region = AWS_REGION)
    Query.new(credentials, method, key, "", expires, now, region, MemoryAlphaProvider)
  end

  def self.upload(credentials, now = Time.now, region = AWS_REGION)
    now = now.utc.beginning_of_day
    Upload.new(credentials, "", "", "", 0, now, region, MemoryAlphaProvider)
  end
end

class LfsSign < S3Sign
  def self.header(credentials, method, key, sha, now = Time.now.utc, region = AWS_REGION)
    Header.new(credentials, method, key, sha, 15.minutes.to_i, now, region, LfsProvider)
  end

  def self.query(credentials, method, key, expires, now = Time.now.utc, region = AWS_REGION)
    Query.new(credentials, method, key, "", expires, now, region, LfsProvider)
  end

  def self.upload(credentials, now = Time.now, region = AWS_REGION)
    now = now.utc.beginning_of_day
    Upload.new(credentials, "", "", "", 0, now, region, LfsProvider)
  end
end
