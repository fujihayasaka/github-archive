# typed: strict
# frozen_string_literal: true

module Marketplace
  module Serializers
    class ReleaseData
      include T::Helpers

      sig { returns(T.nilable(Release)) }
      attr_reader :selected_release

      sig { returns(Release) }
      attr_reader :latest_release

      sig { returns(ActiveRecord::Relation) }
      attr_reader :releases

      sig do
        params(selected_release: T.nilable(Release), latest_release: Release, releases: ActiveRecord::Relation
        ).void
      end
      def initialize(selected_release:, latest_release:, releases:)
        @selected_release = selected_release
        @latest_release = latest_release
        @releases = releases
      end

      sig { returns(Marketplace::Types::SerializedReleaseData) }
      def call
        {
          selectedRelease: serialized_selected_release,
          latestRelease: serialize_release(latest_release),
          releases: releases.map { |release| serialize_release(release) }
        }
      end

      private

      sig { params(release: Release).returns(Marketplace::Types::SerializedRelease) }
      def serialize_release(release)
        {
          tagName: release.tag_name,
          name: release.name,
          isPrerelease: release.prerelease?,
        }
      end

      sig { returns(T.nilable(Marketplace::Types::SerializedRelease)) }
      def serialized_selected_release
        selected_release ? serialize_release(T.must(selected_release)) : nil
      end
    end
  end
end
