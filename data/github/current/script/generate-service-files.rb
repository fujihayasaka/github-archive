#!/usr/bin/env safe-ruby
# typed: true
# frozen_string_literal: true

# generate-service-files.rb <options>
#
# This script is the common entrypoint for generating all service files. When run with default arguments,
# it validates the inputs and writes the following:
# * CODEOWNERS
# * ownership.yaml
# * docs/index.yaml
# * vendor/serviceowners/serviceowners_cache.json
# * vendor/serviceowners/serviceowners_class_cache.json
#
# It supports the following arguments:
# --cache-only: Only generate the two cache files in vendor/serviceowners, skipping validation and other
#               file generation. Used in CI as these cache files are not part of the repository.
# --skip-pattern-file-matches: Skip the cache file generation. The caches are typically not needed in
#                              development and are relatively slow to generate.
# --skip-validation: Skip the validation step. This speeds up stuff in CI. The script SHOULD be called
#                    SOMEWHERE in CI without this option, though, to prevent regressions.
# --stackprof: Generate a stackprof profile of the serviceowners generation process.
#
# Docs: https://thehub.github.com/engineering/development-and-ops/dotcom/serviceowners/serviceowners-usage/
# Please update these if changing the above!

require "github/serviceowners"

if $PROGRAM_NAME == __FILE__
  profile = !!ARGV.delete("--stackprof")
  cache_only = !!ARGV.delete("--cache-only")
  skip_validation = !!ARGV.delete("--skip-validation")

  # Enabling YJIT speeds up cache generation by about 25%
  RubyVM::YJIT.enable if defined?(RubyVM::YJIT) && RubyVM::YJIT.respond_to?(:enable)

  GitHub::Serviceowners::GenerateServiceFiles.run!(profile:, cache_only:, skip_validation:)
end
