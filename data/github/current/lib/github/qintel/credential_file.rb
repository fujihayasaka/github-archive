# typed: true
# frozen_string_literal: true

module GitHub
  module Qintel
    class CredentialFile
      API_BASE_PATH = "/files/%s"
      LOCAL_BASE_PATH = "/data/github/shared/%s"

      attr_reader :uuid, :file, :update_of, :crack_count, :raw

      def initialize(hash:)
        @uuid = hash[:fileuuid]
        @file = hash[:file]
        @update_of = hash[:update_of] || nil
        @crack_count = hash[:crack_count] || 0
        @raw = hash
      end

      # Fetch the data for this credential file.
      #
      # client: - The Qintel::Client instance to use. For testing only.
      # path:   - The path to fetch. For testing only.
      # &blk    - A block to call with fetched credentials.
      #
      # Returns nothing.
      def fetch(client: Qintel.client, path: remote_path)
        raise ArgumentError, "uuid cannot be blank" if uuid.blank?

        tags = [
          "datasource:qintel",
          "version:#{uuid}",
        ]

        local_file_exists = File.exist? local_file_path
        if local_file_exists
          File.open(local_file_path, "r", encoding: "ascii-8bit") do |f|
            GitHub.dogstats.increment("qintel.files.local_cache", tags: tags)
            yield CredentialFile::Parser.new(file: f, uuid: uuid)
          end
        else
          File.open(local_file_path, "w+", encoding: "ascii-8bit") do |f|
            exists_remote = begin
              GitHub::Qintel::S3.exists?(uuid: uuid)
            rescue Aws::S3::Errors::ServiceError
              GitHub.dogstats.increment("qintel.files.s3_existence_error", tags: tags)
            end

            if exists_remote
              begin
                GitHub::Qintel::S3.download(uuid: uuid, file: f)
                GitHub.dogstats.increment("qintel.files.s3_download", tags: tags)
              rescue Aws::S3::Errors::ServiceError
                # If we partially loaded data before the error from s3
                # make sure we clear that data
                f.truncate(0)
                load_from_qintel(client: client, path: path, file: f)
                GitHub.dogstats.increment("qintel.files.s3_download_error", tags: tags)
              end
            else
              load_from_qintel(client: client, path: path, file: f)
              begin
                f.rewind
                GitHub::Qintel::S3.upload(uuid: uuid, file: f)
                GitHub.dogstats.increment("qintel.files.s3_upload", tags: tags)
              rescue Aws::S3::Errors::ServiceError
                GitHub.dogstats.increment("qintel.files.s3_upload_error", tags: tags)
              end
            end
            yield CredentialFile::Parser.new(file: f, uuid: uuid)
          end
        end
      end

      def remote_path
        API_BASE_PATH % uuid
      end

      def local_file_path
        CredentialFile.get_local_file_path uuid
      end

      def self.get_local_file_path(uuid)
        LOCAL_BASE_PATH % uuid
      end

      class Parser
        attr_reader :file, :uuid

        def initialize(file:, uuid: nil)
          @file = file
          @uuid = uuid
        end

        def parse_credentials_from_file(start: nil, amount: nil)
          lines = []
          File.open(file.path, encoding: "utf-8") do |f|
            f.each_line.with_index do |line, idx|
              next if start && idx < start
              break if amount && idx >= (start || 0) + amount

              begin
                lines << JSON.parse(line)
              rescue Yajl::ParseError => e
                Failbot.report(e)
                next
              end
            end
          end
          lines
        end
      end

      private

      def load_from_qintel(client:, path:, file:)
        client.get(path) do |chunk|
          file.write(chunk)
        end
        file.flush
      end
    end
  end
end
