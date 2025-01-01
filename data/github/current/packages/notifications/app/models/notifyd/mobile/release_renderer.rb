# typed: strict
# frozen_string_literal: true

module Notifyd
  module Mobile
    class ReleaseRenderer

      sig { params(release: ::Release, author: Author).void }
      def initialize(release:, author:)
        @release = release
        @author = author
      end

      sig { returns(Notifyd::Proto::Layouts::Mobile::Basic) }
      def render
        thread = ReleaseThread.new(release: release)

        release_info = release.prerelease? ? "Pre-release" : "Release"
        release_info += " #{release.tag.name_for_display}" if release.tagged?

        title = "#{release_info} - #{release.display_name}"
        subtitle = Subtitle.new(repository: release.repository, number: nil)

        Notifyd::Proto::Layouts::Mobile::Basic.new(
          title: title,
          subtitle: subtitle.to_s,
          body: release.body,
          url: release.permalink,
          avatar_url: author.avatar_url,
          author_profile_name: author.profile_name,
          author_username: author.username,
          thread_id: thread.id,
          thread_type: thread.type,
        )
      end

      private

      sig { returns(::Release) }
      attr_reader :release
      sig { returns(Author) }
      attr_reader :author
    end
  end
end
