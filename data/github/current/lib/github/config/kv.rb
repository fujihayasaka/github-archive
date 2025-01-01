# typed: true
# frozen_string_literal: true

##
# Setup global key-value object.
#
# Use `GitHub.kv` anywhere in GitHub to access a key-value store.
#
# This should be used in all new code instead of Redis.
#
# Docs for KV can be found in https://github.com/github/github-kv
require "application_record/domain/key_values"
require "github"
require "github-ds"

# Replace KV from github-ds with the one from github-kv
GitHub.send(:remove_const, :KV)
GitHub.send(:remove_const, :Result)

require "github_kv"

module GitHub
  Result = GitHub::KV::Result

  class KV
    # no-op for the new github-kv; ActiveRecord will take care of this for us
    def self.BINARY(string) # rubocop:disable Naming/MethodName
      string
    end
  end
end

require "github/ds_extensions"

module GitHub
  module Config
    module KV
      attr_writer :kv

      ::GitHub::KV.configure do |config|
        config.encapsulated_errors = [
          ActiveRecord::ConnectionFailed,
          ActiveRecord::ConnectionNotEstablished,
          ActiveRecord::NoDatabaseError,
        ]
        config.use_local_time = GitHub::AppEnvironment.test?
      end

      def kv
        @kv ||= ::GitHub::KV.new do
          ApplicationRecord::Domain::KeyValues.connection
        end
      end
    end
  end

  extend Config::KV
end
