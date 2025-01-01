# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module OctoshiftStorage
      # Details for Octoshift's Memory Alpha storage.
      attr_accessor :octoshift_memory_alpha_bucket
      attr_accessor :octoshift_memory_alpha_key_id
      attr_accessor :octoshift_memory_alpha_access_key
    end
  end

  extend Config::OctoshiftStorage
end
