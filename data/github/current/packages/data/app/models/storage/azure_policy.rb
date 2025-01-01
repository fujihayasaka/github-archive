# typed: true
# frozen_string_literal: true

module Storage
  # This policy defines how files are stored and accessed using ABS
  #
  # IMPORTANT NOTE: Due to missing features and security shortfalls in Azure's URL
  # signing algorithm, this Policy will only work with Alambic's uploader. Please
  # check with the Data Architecture team before making use of this policy. For Azure use,
  # most Uploadable types should leverage `MemoryAlphaWithDirectAbsDownloadPolicy`
  class AzurePolicy < Storage::Policy
    # Format block ids as a 32-bit binary string, padded with leading zeroes
    BLOCK_ID_FORMAT = "%032b"

    def azure_sign
      @azure_sign ||= AzureSign.new(@uploadable)
    end

    def using_cdn?(uploadable)
      false
    end

    def download_url(_ = nil, expiration: nil)
      now = Time.now
      azure_sign.generate_signed_blob_url(:read, expiration)
    ensure
      stats_timing(:download, start: now) if now
    end

    def upload_url
      azure_sign.generate_signed_blob_url(:write)
    end

    def deletion_url
      azure_sign.generate_signed_blob_url(:delete)
    end

    def multi_part_upload_url_headers(state)
      url = ""
      headers = {}
      case state
      when "starter"
        # Azure has no "Start Upload" operation. As such, return an empty
        # URL. Alambic will interpret this as "skip this operation"

      when "multipart_upload_started"
        # Alambic will submit the `part_sha` alongside the policy request.
        # Here, `part_sha` is the MD5 hash of the block being uploaded
        url = "#{upload_url}&comp=block&blockid=#{get_block_id}"
        headers["Content-MD5"] = content_md5

      when "multipart_upload_list_parts"
        # Alambic uses this to get the list of blocks to submit when completing
        # the upload. As Uploadables are immutable, we only care about
        # uncommitted blocks
        url = "#{download_url}&comp=blocklist&blocklisttype=uncommitted"

      when "multipart_upload_completed"
        # Alambic will submit the `part_sha` alongside the policy request.
        # Here, `part_sha` is the MD5 hash of the block list being
        # committed
        url = "#{upload_url}&comp=blocklist"
        headers["Content-MD5"] = content_md5

      end

      { url: url, headers: headers }
    end

    def policy_hash
      # Azure does not support form-based uploads. Therefore, we should never include a `:form` when generating a
      # policy
      h = super
      h.delete(:form)
      h
    end

    def delete_object
      return if Rails.env.test? && self.class.faraday.nil?
      self.class.faraday.delete do |req|
        req.url(deletion_url)
      end
    end

    # The base upload_contents method requires form-based uploads, which the AzurePolicy does not support. As
    # such, raise an error to prevent it from being called
    def upload_contents(io)
      raise NotImplementedError
    end

    private

    def content_md5
      packed_md5 = [@uploadable.part_sha].pack("H*")

      Base64.encode64(packed_md5).chomp
    end

    def same_origin_upload?
      false
    end

    def upload_form
      {}
    end

    def upload_header
      {
        "Content-Type" => @uploadable.content_type,
        "x-ms-blob-type" => "BlockBlob"
      }
    end

    # Azure Block IDs are required to be:
    # - Base64 encoded
    # - Less than 64 bytes before encoding
    # - Of equal length for a given blob
    def get_block_id
      id = BLOCK_ID_FORMAT % @uploadable.part_number
      Base64.strict_encode64(id)
    end
  end
end
