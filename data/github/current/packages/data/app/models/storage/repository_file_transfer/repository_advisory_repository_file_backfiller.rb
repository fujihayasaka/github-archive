# typed: strict
# frozen_string_literal: true

module Storage::RepositoryFileTransfer
  class RepositoryAdvisoryRepositoryFileBackfiller
    class FilteredUrl < T::Struct
      const :url, String, default: ""
      const :file_id, Integer, default: 0
      const :name, String, default: ""
    end

    sig { returns(T.nilable(User)) }
    attr_reader :actor

    sig { returns(ActiveRecord::Base) }
    attr_reader :target

    URI_REGEX = /\/user-attachments\/files\/(?<file_id>\d+)\/(?<name>.+)/

    sig { params(text: T.nilable(String)).returns(T::Array[String]) }
    def self.extract_urls_from_text(text)
      return [] unless text
      # For some reason, urls wrapped in parentheses are being extracted with the closing parenthesis included.
      # E.g.
      #   URI.extract("\n\n![Image](http://github.localhost/some/path)\n\n", ["https", "http"])
      #   => ["http://github.localhost/some/path)"]
      URI.extract(text, %w[http https]).map { |url| url.delete(")") }.uniq
    end

    sig do
      params(
        repository_advisory: RepositoryAdvisory,
        actor: T.nilable(User),
        urls: T::Array[String]
      ).void
    end
    def self.backfill_upload_container_ids(repository_advisory, actor, urls)
      new(repository_advisory, actor).backfill_upload_container_ids(urls)
    end

    sig { params(target: ActiveRecord::Base, actor: T.nilable(User)).void }
    def initialize(target, actor)
      @target = target
      @actor = actor
    end

    sig { params(urls: T::Array[String]).void }
    def backfill_upload_container_ids(urls = [])
      return if actor.nil?

      filtered_urls = filter_urls(urls)
      return if filtered_urls.empty?

      file_ids = filtered_urls.map(&:file_id)
      repository_files = RepositoryFile.where(uploader_id: actor&.id, id: file_ids, upload_container_type: RepositoryAdvisory.name, upload_container_id: nil)
      return if repository_files.empty?

      repository_files.update_all(upload_container_id: repository_advisory.id)
    end

    sig { returns(RepositoryAdvisory) }
    def repository_advisory
      T.cast(target, RepositoryAdvisory)
    end

    private

    sig { params(urls: T::Array[String]).returns(T::Array[FilteredUrl]) }
    def filter_urls(urls)
      filtered_data = []
      unique_urls = urls.uniq

      unique_urls.each do |url|
        uri = parse_uri(url)
        next if uri.nil? || !is_uri_valid?(uri)
        match = uri.request_uri.match(URI_REGEX)
        next unless match
        file_id = match[:file_id].to_i

        filtered_data << FilteredUrl.new(
          url: url,
          file_id: file_id
        )
      end

      filtered_data
    end

    sig { params(url: String).returns(T.nilable(Addressable::URI)) }
    def parse_uri(url)
      begin
        Addressable::URI.parse(url)
      rescue Addressable::URI::InvalidURIError => error
        nil
      end
    end

    sig { params(uri: Addressable::URI).returns(T::Boolean) }
    def is_uri_valid?(uri)
      uri.present? && uri.host.present? && is_github_url?(uri.host) && uri.request_uri != "/"
    end

    sig { params(host: String).returns(T::Boolean) }
    def is_github_url?(host)
      GitHub.image_proxy_host_allowlist.any? do |test|
        # We call sub(/:.*/, "") because sometimes in Codespaces the port is included in the host_name and the host
        # coming from an Addressable::URI will not have the port included.
        test.is_a?(String) ? host == test.sub(/:.*/, "") : test.match(host)
      end
    end
  end
end
