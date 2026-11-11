# typed: false
# frozen_string_literal: true

module Storage
  class Policy
    class HttpError < StandardError
      attr_reader :status
      attr_reader :uploadable_class
      attr_reader :id

      def initialize(status, klass, id, msg)
        @status = status
        @uploadable_class = klass
        @id = id
        super(msg)
      end
    end

    @@faraday = nil

    def self.set_faraday_adapter(*adapter_args)
      @@faraday = Faraday.new do |f|
        f.request :multipart
        f.request :url_encoded
        f.adapter(*adapter_args)
      end
    end

    def self.faraday
      return @@faraday if @@faraday || Rails.env.test?
      set_faraday_adapter(Faraday.default_adapter)
    end

    def self.stub_faraday
      stub = Faraday::Adapter::Test::Stubs.new
      set_faraday_adapter(:test, stub)
      stub
    end

    def self.faraday=(f)
      @@faraday = f
    end

    attr_reader :actor
    attr_reader :repository
    attr_reader :key
    attr_reader :remote_auth_params

    # Builds a new Policy.
    #
    # uploadable - Instance of the ActiveRecord model that is being uploaded.
    # actor      - The optional User accessing the uploadable.
    # repository - The optional Repository that the uploadable belongs to.
    # key        - The optional PublicKey that is accessing the uploadable.
    def initialize(uploadable, actor: nil, repository: nil, key: nil)
      @uploadable = uploadable
      @actor = actor
      @repository = repository
      @key = key
      @remote_auth_params = {}
    end

    def repository_full_name
      @repository.try(:name_with_owner)
    end

    def public_repository?
      @repository.try(:public?)
    end

    def repository_id
      @repository.try(:id).to_i
    end

    def policy_hash
      now = Time.now
      h = {
        upload_url: upload_url,
        header: upload_header,
        asset: asset_hash,
        form: upload_form,
        same_origin: same_origin_upload?,
      }

      if @uploadable.respond_to?(:supports_multi_part_upload) && @uploadable.supports_multi_part_upload
        url_headers = multi_part_upload_url_headers(@uploadable.state)
        h[:upload_url] = url_headers[:url]
        h[:header] = url_headers[:headers]
        h[:guid] = @uploadable.guid
        h.delete(:form)
      end

      if url = asset_upload_url
        h[:asset_upload_url] = url
      end

      h
    ensure
      stats_timing(:upload, start: now) if now
    end

    def asset_hash
      h = {
        id: @uploadable.id,
        name: @uploadable.name,
        size: @uploadable.size,
        content_type: @uploadable.content_type,
        href: @uploadable.storage_external_url,
      }

      if @uploadable.respond_to?(:storage_metadata_url)
        h[:metadata_url] = @uploadable.storage_metadata_url
      end

      if @uploadable.respond_to?(:original_name)
        h[:original_name] = @uploadable.original_name
      end

      if @uploadable.respond_to?(:replaced_asset)
        h[:replaced_asset] = @uploadable.replaced_asset
      end

      h
    end

    def storage_supports_multi_part_upload
      false
    end

    def download_url(_ = nil)
      raise NotImplementedError
    end

    def metadata_url(_ = nil)
      raise NotImplementedError
    end

    def upload_url
      raise NotImplementedError
    end

    def multi_part_upload_url_headers
      raise NotImplementedError
    end

    def upload_contents(io)
      info = policy_hash
      self.class.faraday.post(info[:upload_url]) do |req|
        req.headers["Content-Type"] = "multipart/form-data"
        req.body = {}
        info[:header].each do |key, value|
          req.headers[key] = value
        end
        info[:form].each do |key, value|
          req.body[key.to_s] = value
        end
        req.body["file"] = Faraday::UploadIO.new(io, @uploadable.content_type)
      end
    end

    def upload_contents!(io)
      res = upload_contents(io)
      if res.status < 200 || res.status > 299
        GitHub.logger.info(
          "upload contents failed: #{res.body}",
          {
            "code.function": __method__,
            "http.status_code": res.status,
            "gh.storage_policy.uploadable": @uploadable.inspect
          }
        )
        raise HttpError.new(res.status, @uploadable.class, @uploadable.id,
          "Error uploading for #{@uploadable.class} ##{@uploadable.id}: HTTP #{res.status}")
      end
    end

    def storage_policy_api_url
      if @uploadable.respond_to?(:storage_policy_api_url)
        @uploadable.storage_policy_api_url unless @uploadable.new_record?
      end
    end

    def stats_timing(op, start:)
      ms = (Time.now - start) * 1000
      GitHub.dogstats.timing("storage_policy.url", ms, tags: [
        "policy:#{self.class.name.underscore.sub(/\Astorage\//, "").chomp("_policy")}",
        "model:#{@uploadable.class.name.underscore}",
        "provider:#{@uploadable.storage_provider}",
        "op:#{op}",
      ])
    end

    private

    def upload_form
      asset_hash.except(:href, :replaced_asset)
    end

    def same_origin_upload?
      true
    end

    def upload_header
      {}
    end

    def asset_upload_url
      "/upload/#{@uploadable.storage_verify_path}"
    end
  end
end
