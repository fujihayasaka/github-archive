#!/usr/bin/env ruby
# typed: true
# frozen_string_literal: true

# This script calculates the base Ruby version to a stable release one minor version behind production Ruby.
# It outputs the base Ruby version release information to a temporary directory.

require "fileutils"
require "json"
require "open-uri"
require "open3"
require "yaml"

# Helper to run a shell command and return stdout
def sh(cmd)
  output, status = Open3.capture2(cmd)
  unless status.success?
    warn "Command failed: #{cmd}"
    exit 1
  end
  output.strip
end

# Get the current production Ruby version
prod_ruby_version = sh("bin/safe-ruby --version").split[1]
puts "Production Ruby version: #{prod_ruby_version}"

major, minor, *_ = prod_ruby_version.split(".").map(&:to_i)

# Calculate the previous minor version
if minor == 0
  prev_major = major - 1
  base_ruby_prev_minor_version = "#{prev_major}."
else
  prev_minor = minor - 1
  base_ruby_prev_minor_version = "#{major}.#{prev_minor}"
end
puts "Previous minor version: #{base_ruby_prev_minor_version}"

# Get the stable Ruby version matching the previous minor version
downloads_yml_url = "https://raw.githubusercontent.com/ruby/www.ruby-lang.org/refs/heads/master/_data/downloads.yml"
downloads_io = URI.open(downloads_yml_url)
unless downloads_io
  warn "Failed to open #{downloads_yml_url}"
  exit 1
end
downloads = YAML.safe_load(downloads_io.read)
stable_versions = downloads["stable"] || []
base_ruby_version = stable_versions.find { |v| v.start_with?(base_ruby_prev_minor_version) }
puts "Base Ruby version: #{base_ruby_version}"

# Get the URL and SHA256 for the base Ruby version
releases_yml_url = "https://raw.githubusercontent.com/ruby/www.ruby-lang.org/refs/heads/master/_data/releases.yml"
releases_io = URI.open(releases_yml_url)
unless releases_io
  warn "Failed to open #{releases_yml_url}"
  exit 1
end
releases = YAML.safe_load(releases_io.read, permitted_classes: [Date])

release = releases.find { |r| r["version"] == base_ruby_version }
if release
  url_gz = release.dig("url", "gz")
  sha256_gz = release.dig("sha256", "gz")
  post = release["post"]
  puts "Base Ruby URL: #{url_gz}"
  puts "Base Ruby SHA256: #{sha256_gz}"
  puts "post: #{post}"
else
  warn "Could not find release info for version #{base_ruby_version}"
  exit 1
end

FileUtils.mkdir_p("/tmp/prepare-base-ruby-update-artifacts")
File.write("/tmp/prepare-base-ruby-update-artifacts/BASE_RUBY_VERSION", "#{base_ruby_version}\n")
File.write("/tmp/prepare-base-ruby-update-artifacts/BASE_RUBY_URL", "#{url_gz}\n")
File.write("/tmp/prepare-base-ruby-update-artifacts/BASE_RUBY_SHA256", "#{sha256_gz}\n")
File.write("/tmp/prepare-base-ruby-update-artifacts/BASE_RUBY_POST", "#{post}\n")
