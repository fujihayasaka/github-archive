# frozen_string_literal: true

require "test_helper"

module AdvisoryDB
  # A set of tests to ensure that Ruby versions are consistent across the repo.
  #
  # TODO: these are really more linting tests than integration tests. We should
  # port them to custom RuboCop cops.
  class RubyVersionMatchesTest < ActionDispatch::IntegrationTest
    # Seeing this error? 🙀 Don't fret! 🧘‍♀️
    #
    # This test shouldn't ever fail because rbenv will prevent tests from
    # running at all if the version of Ruby specified in .ruby-version is not
    # installed. If you're seeing this message, it might indicate the
    # .ruby-version file was removed. Unless you're removing all of the
    # functionality that relies on that file existing, you can just add it back.
    test "installed version of Ruby matches version in .ruby-version file" do
      assert_equal File.read(".ruby-version").strip, RUBY_VERSION, "Expected installed version of Ruby to match version specified in .ruby-version"
    end

    # The Dockerfile is ignored via dockerignore, so we can't read from it in
    # CI. We'll have to settle for catching this via local tests.
    unless ENV["CI_MODE"] == "true"
      # Seeing this error? 🙀 Don't fret! 🧘‍♀️
      #
      # This test makes sure that that ruby builder image in our docker file uses a
      # major-minor variant that matches that of the Ruby version in our
      # .ruby-version file. If you're seeing this error, it likely means that one
      # of the two changed without the other one being updated to match.
      test "major-minor version of Ruby from .ruby-version matches Ruby image variant in Dockerfile" do
        dockerfile_path = File.expand_path("Dockerfile", Rails.root)
        ruby_version_path = File.expand_path(".ruby-version", Rails.root)
        dockerfile_major_minor = dockerfile_ruby_variant(dockerfile_path)
        ruby_version_major_minor = File.read(ruby_version_path).strip.match(/^(\d+\.\d+)/)&.[](1)

        assert_equal ruby_version_major_minor, dockerfile_major_minor, "Expected major-minor version of Ruby from .ruby-version to match Ruby image variant in Dockerfile"
      end

      # Seeing this error? 🙀 Don't fret! 🧘‍♀️
      #
      # This test ensures that our toolkit cibuild script runs tests on at least
      # one build image that uses the same major-minor Ruby variant as the build
      # image in the Dockerfile. If you're seeing this error just add another test
      # run to the script that uses the image file from the build kit. (Just the
      # image name, we don't care about the SHA256 digest; e.g.
      # `ghcr.io/github/gh-base-image/ruby-builder:v3.3-focal`)
      test "build image in Dockerfile has a matching toolkit cibuild script" do
        dockerfile_path = File.expand_path("Dockerfile", Rails.root)
        main_toolkit_cibuild_path = File.expand_path("script/cibuild-advisory-db-toolkit", Rails.root)
        # TODO: add an assertion that the number of files matching the variant
        # pattern is the same as the number of variant paths in the array
        toolkit_cibuild_variant_paths = [
          File.expand_path("script/cibuild-advisory-db-toolkit-3.2", Rails.root),
          File.expand_path("script/cibuild-advisory-db-toolkit-3.3", Rails.root),
        ]
        dockerfile_ruby_variant = dockerfile_ruby_variant(dockerfile_path)
        toolkit_cibuild_ruby_variants = [
          main_toolkit_cibuild_ruby_variant(main_toolkit_cibuild_path),
        ] + toolkit_cibuild_variant_paths.map do |variant_path|
          toolkit_cibuild_variant_ruby(variant_path, main_toolkit_cibuild_path)
        end

        assert_includes toolkit_cibuild_ruby_variants, dockerfile_ruby_variant, <<~ERROR
          Expected script/cibuild-advisory-db-toolkit to specify at least one build image \
          that uses the same major-minor Ruby variant as the build image in the Dockerfile
        ERROR
      end
    end

    def dockerfile_ruby_variant(dockerfile_path)
      build_image_base = "ghcr.io/github/gh-base-image/ruby-builder"
      variant_regex = /^FROM #{build_image_base}:v(\d+\.\d+)(?![\d.])/
      ruby_variant = File.read(dockerfile_path).match(variant_regex)&.[](1)
      assert_predicate ruby_variant, :present?, "Expected to find build image #{build_image_base} using a major-minor Ruby variant in #{dockerfile_path}"
      ruby_variant
    end

    def main_toolkit_cibuild_ruby_variant(main_toolkit_cibuild_path)
      variant_regex = /^RUBY_VARIANT=\$\{RUBY_VARIANT:-(\d+\.\d+)\}$/
      ruby_variant = File.read(main_toolkit_cibuild_path).match(variant_regex)&.[](1)
      assert_predicate ruby_variant, :present?, "Expected to find RUBY_VARIANT set to a major-minor Ruby variant in #{main_toolkit_cibuild_path}"
      ruby_variant
    end

    def toolkit_cibuild_variant_ruby(variant_file_path, main_toolkit_cibuild_path)
      main_toolkit_cibuild_file_name = main_toolkit_cibuild_path.split("/").last
      variant_file_path_name = variant_file_path.split("/").last
      variant_regex = %r{^RUBY_VARIANT=(\d+\.\d+)\s+script/#{main_toolkit_cibuild_file_name}}
      ruby_variant = File.read(variant_file_path).match(variant_regex)&.[](1)
      assert_predicate ruby_variant, :present?, "Expected to find RUBY_VARIANT set to a major-minor Ruby variant passed to #{main_toolkit_cibuild_file_name} in #{variant_file_path}"
      assert_equal variant_file_path_name, "#{main_toolkit_cibuild_file_name}-#{ruby_variant}", "Expected #{variant_file_path_name} to be named after the major-minor Ruby variant that is sets: #{main_toolkit_cibuild_file_name}-#{ruby_variant}"
      ruby_variant
    end
  end
end
