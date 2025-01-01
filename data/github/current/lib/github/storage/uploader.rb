# typed: true
# frozen_string_literal: true

module GitHub::Storage
  class Uploader

    class Error < StandardError
      def initialize(uploader, message)
        @uploader = uploader
        super(message)
      end
    end

    def self.perform(opts)
      new(**opts).perform
    end

    attr_reader :fileservers, :oid, :file

    def initialize(fileservers:, oid:, file:)
      @fileservers = fileservers
      @oid = oid
      @file = file
    end

    def perform
      ok = upload_file
      raise Error.new(self, upload_error) unless ok
      return self if fileservers.size == 1
      ok, obj = replicate_to_fileservers
      raise Error.new(self, replicate_error(obj["errors"])) unless ok
      self
    end

    def upload_error
      "Failed to upload #{oid} to #{origin_host}"
    end

    def replicate_error(errors)
      string = "Failed to replicate:"
      errors.each do |host, message|
        string += "\n  #{host} #{message}"
      end
      string
    end

    def origin_host
      @origin_host ||= URI.parse(fileservers.first).host
    end

    def upload_file
      response = GitHub::Storage::Client.upload(origin_host, oid, file)
      response.first
    end

    def replicate_to_fileservers
      ok, body = GitHub::Storage::Client.replicate_to(origin_host, [
        {
          oid: oid,
          fileservers: fileservers[1..-1],
        },
      ])

      [ok, Array(body["objects"]).first]
    end
  end
end
