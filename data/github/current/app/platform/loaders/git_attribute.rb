# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class GitAttribute < Platform::Loader
      ATTRIBUTE_KEYS = %W(
        linguist-documentation
        linguist-generated
        linguist-vendored
        linguist-language
        linguist-encoding
      ).freeze

      def self.load(repository, path, commit_oid)
        return Promise.resolve({}) if path.nil?
        return Promise.resolve({}) unless GitRPC::Util.valid_full_sha1?(commit_oid)

        self.for(repository, commit_oid).load(path)
      end

      def initialize(repository, commit_oid)
        @repository = repository
        @commit_oid = commit_oid
      end

      def fetch(paths)
        GitHub.dogstats.time("blob.attributes.load") do
          repository.rpc.read_attributes(commit_oid, paths, keys: ATTRIBUTE_KEYS).transform_values(&:compact)
        end
      end

      private

      attr_reader :repository, :commit_oid
    end
  end
end
