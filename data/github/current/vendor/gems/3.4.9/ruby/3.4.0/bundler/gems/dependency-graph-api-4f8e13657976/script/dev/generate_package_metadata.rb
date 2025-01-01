#!/usr/bin/env ruby
#
# Usage: bin/rails r script/dev/generate_package_metadata.rb
#
# This scripts emits a PackageMetadata event with random valid
# information that can be used for testing purposes. It assumes
# you have a Kafka broker running in port 9092.

require "securerandom"
require_relative "../../config/environment"
require_relative "../../proto/hydro/schemas/package_license_gateway/clearlydefined/v0/package_metadata_pb.rb"
require_relative "local_hydro_helpers.rb"

def words
  return @words if defined?(@words)
  @words = File.read("/usr/share/dict/words").split("\n")
rescue StandardError => se
  puts "Can't find dictionary file (/usr/share/dict/words). Try 'sudo apt install wamerican' and re-run the script"
  exit(1)
end

def random_word
  return words.sample.gsub(/[^A-Za-z]+/, "")
end

def random_git_sha
  SecureRandom.hex(20)
end

def random_semver
  "#{rand(100)}.#{rand(100)}.#{rand(100)}"
end

def random_spdx_license
  %w(Apache-2.0 MIT BSD-2-Clause BSD-3-Clause MPL-2.0 GPL-2.0 AGPL-3.0 CC0-1.0).sample
end

# TODO: revisit this when we have the authoritative list
# https://github.slack.com/archives/C03Q3FZ9RFG/p1683232777747739
def random_type
  [
    { type: "npm", provider: "npmjs" },
    { type: "gem", provider: "rubygems" },
    { type: "go", provider: "golang" },
    { type: "crate", provider: "cratesio" },
    { type: "pypi", provider: "pypi" },
    { type: "nuget", provider: "nuget" },
    { type: "php", provider: "composer" },
    { type: "git", provider: "github" },
    { type: "maven", provider: "maven" },
  ].sample
end

# hydro.schemas.package_license_gateway.clearlydefined.v0.entities.PackageCoordinates
def random_coordinates
  t = random_type

  {
    type: t[:type],
    provider: t[:provider],
    namespace: random_word,
    name: random_word,
    revision: random_semver,
  }
end

# hydro.schemas.package_license_gateway.clearlydefined.v0.entities.PackageWeblinks
def random_weblinks
  repo = "https://github.com/#{random_word}/#{random_word}"

  {
    repository: repo,
    project_website: repo,
    issue_tracker: "#{repo}/issues",
  }
end

# Examples taken from https://github.com/github/package-license-gateway/pull/29
# hydro.schemas.package_license_gateway.clearlydefined.v0.entities.Score
def random_score
  s = {
    declared: rand(30),
    discovered: rand(30),
    consistency: rand(15),
    spdx: rand(15),
    texts: rand(10),
  }
  s[:total] = s[:declared] + s[:discovered] + s[:consistency] + s[:spdx] + s[:texts]

  s
end

attributions = ["Copyright (c) Monalisa, 2023"]
default_topic = "package_license_gateway.clearlydefined.v0.PackageMetadata"

options = {
  num_events: 1,
  topic: default_topic,
  dry_run: false,
}
OptionParser.new do |opts|
  opts.on("-n", "--num_events <INT>", Integer, "Number of OSPO events to publish (default: 1)") do |n|
    options[:num_events] = n
  end
  opts.on("-t", "--topic <STRING>", String, "Full name of topic to publish to (default: #{default_topic}") do |t|
    options[:topic] = t
  end
  opts.on("-d", "--dry-run", "Only log each message without publishing to Hydro topic") do
    options[:dry_run] = true
  end
end.parse!

options[:num_events].times do |n|
  # hydro.schemas.package_license_gateway.clearlydefined.v0.PackageMetadata
  message = {
    coordinates: random_coordinates,
    license_spdx_expression: random_spdx_license,
    uris: random_weblinks,
    release_date: Time.now.utc,
    score: random_score,
    git_sha: random_git_sha,
    attributions: attributions,
  }

  puts "#{options[:dry_run] ? "Logging" : "Publishing to topic: #{options[:topic]}"} message(#{n}):\n#{message}\n"

  publish(message,
          topic: options[:topic],
          schema: "hydro.schemas.package_license_gateway.clearlydefined.v0.PackageMetadata") unless options[:dry_run]
end
