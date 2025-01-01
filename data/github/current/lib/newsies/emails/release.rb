# typed: true
# frozen_string_literal: true

module Newsies
  module Emails
    class Release < Newsies::Emails::Message
      include ActionView::Helpers::TextHelper

      def self.matches?(comment)
        comment.is_a?(::Release)
      end

      sig { returns ::Release }
      def release
        comment
      end

      def subject
        release_info = release.prerelease? ? "Pre-release" : "Release"
        release_info += " #{release.tag.name_for_display}" if release.tagged?

        "[#{repository.name_with_display_owner}] #{release_info} - #{release.display_name}"
      end

      # You can't reply to a Release since it only ever sends one notification.
      def tokenized_list_address
        GitHub.urls.noreply_address
      end

      # Can't unsubscribe from an individual Release thread either.
      def tokenized_unsubscribe_address
      end

      # Prepend title and meta info before the release body and append asset information after it
      def content_html
        safe_join([header_html, super, asset_html].compact, "\n\n")
      end

      # Override footer to customize unsubscribe link.
      def footer_html
        msg = safe_join([
          Newsies::Emails::Message::MDASH,
          tag("br"),
          "You are receiving this because you are watching this repository.",
          tag("br"),
          link_to("View it on #{GitHub.flavor}", url),
          " or ",
          link_to("unsubscribe", unsubscribe_from_repository_url),
          " from all notifications for this repository.",
        ])

        msg += mark_read_image if tracking_image_enabled?

        content_tag(:p, msg, style: "font-size:small;-webkit-text-size-adjust:none;color:#666;")
      end

      private

      MIDDOT = GitHub::HTMLSafeString.make(" &middot; ")
      def header_html
        meta_info = [safe_join(["Repository: ", repository_link])]
        meta_info << safe_join(["Tag: ", tag_link]) if release.tagged?
        meta_info << safe_join(["Commit: ", commit_link]) if release.tagged?
        meta_info << safe_join(["Released by: ", author_link]) if release.author

        header = [
          content_tag(:h1, release_link),
          content_tag(:p, safe_join(meta_info, MIDDOT), style: "font-size:small;-webkit-text-size-adjust:none;"),
        ]

        safe_join(header)
      end

      def asset_html
        assets = release.uploaded_assets.map(&:display_name)
        # Tagged assets will also have source code downloads available
        assets += ["Source code (zip)", "Source code (tar.gz)"] if release.tagged?

        return unless assets.length > 0

        safe_join([
          Newsies::Emails::Message::MDASH,
          content_tag(:p, "This release has #{pluralize(assets.length, "asset")}:"),
          content_tag(:ul, safe_join(assets.map { |asset| content_tag(:li, asset) })),
          content_tag(
            :p,
            safe_join([
              "Visit the ",
              release_link(text: "release page"),
              " to download #{assets.length == 1 ? "it" : "them"}.",
          ])),
        ])
      end

      def unsubscribe_from_repository_url
        token = Newsies::Authentication.token(:unsubscribe, settings_user, repository.id)
        "#{repository.permalink}/unsubscribe_via_email/#{token}"
      end

      def release_link(text: release.display_name)
        content_tag(:a, text, href: url)
      end

      def repository_link
        content_tag(:a, repository.name_with_display_owner, href: repository.permalink)
      end

      def tag_link
        content_tag(:a, release.tag.name_for_display, href: GitHub.url + tree_path("", release.tag.name_for_display, release.repository))
      end

      def commit_link
        content_tag(:a, release.tag.commit.abbreviated_oid, href: GitHub.url + commit_path(release.tag.commit, release.repository))
      end

      def author_link
        content_tag(:a, release.author&.display_login, href: GitHub.url + user_path(release.author))
      end
    end
  end
end
