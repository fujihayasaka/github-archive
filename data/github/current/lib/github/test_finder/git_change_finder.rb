# typed: true
# frozen_string_literal: true

require "fileutils"

module GitHub
  module TestFinder
    class GitChangeFinder
      def self.all(within: Rails.root, merge_base_ref:, force_since_merge_base: false)
        @__changes ||= {}

        hash_key = "#{merge_base_ref}-#{force_since_merge_base}"
        @__changes[hash_key] ||= self.find_all(within:, merge_base_ref:, force_since_merge_base:)
      end

      def self.find_all(within: Rails.root, merge_base_ref:, force_since_merge_base: false)
        change_finder = new(within, merge_base_ref)
        uncommitted = change_finder.uncommitted

        if uncommitted.empty? || force_since_merge_base
          uncommitted.concat(change_finder.since_merge_base) # Include uncommitted changes if force_since_merge_base is true
        else
          uncommitted
        end
      end

      attr_reader :path, :merge_base_ref
      def initialize(path, merge_base_ref)
        @path = path
        @merge_base_ref = merge_base_ref
      end

      def uncommitted
        FileUtils.cd(path) do
          files = `git diff --name-only`.lines.map(&:chomp)
          files += `git diff --name-only --cached`.lines.map(&:chomp)
          files += `git ls-files --others --exclude-standard`.lines.map(&:chomp)
        end
      end

      def since_merge_base
        FileUtils.cd(path) do
          `git diff #{merge_base}... --name-only`.lines.map(&:chomp)
        end
      end

      def merge_base
        FileUtils.cd(path) do
          `git merge-base HEAD #{merge_base_ref}`.chomp
        end
      end
    end
  end
end
