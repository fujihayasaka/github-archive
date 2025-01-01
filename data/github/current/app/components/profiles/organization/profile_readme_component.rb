# typed: true
# frozen_string_literal: true

module Profiles
  module Organization
    class ProfileReadmeComponent < ApplicationComponent
      attr_reader :profile, :organization

      def initialize(profile:)
        @profile = profile
        @organization = profile.organization
      end

      def render?
        profile.visible?
      end

      def profile_readme
        profile.readme
      end

      def profile_repository
        profile.repository
      end

      def readme_visibility_label
        profile.public? ? "Public" : "Private"
      end
    end
  end
end
