# typed: true
# frozen_string_literal: true
#
# Matches embedded videos in user-supplied content in one of two formats:
#
# 1. As a video tag, like <video
#    src="https://user-images.githubusercontent.com/7559041/1234.mp4"></video>
#
# 2. As a github-flavored markdown target of a link, like
# <p><a href="https://user-images.githubusercontent.com/7559041/1234.mp4">…</a></p>.
#
# In both cases, the provided URL must be a valid github user asset host.
#
# In the GitHub-flavored markdown text, the plain text was converted to a link
# by the markdown processor.
#
# Video Tag References
# =====================
#
# Valid Video tag references text references are transformed into a tag that looks like this:
#
#   <video
#     gh:video-upload='{"src":"https://user-images.githubusercontent.com/7559041/1234.mp4"}'
#     src="https://user-images.githubusercontent.com/7559041/1234.mp4"><video>
#
# GH-Flavored Markdown References
# =====================
#
# Valid Video tag references text references are transformed into a tag that looks like this:
#
#   <p gh:video-upload='{"src":"https://user-images.githubusercontent.com/7559041/1234.mp4"}'>
#    <a href="https://user-images.githubusercontent.com/7559041/1234.mp4">https://user-images.githubusercontent.com/7559041/1234.mp4</a>
#   </p>
#
# In both cases the `gh:video-upload["src"]` will be used by the GitHub::Goomba::Async::VideoTagFilter
# to find the associated `UserAsset` object. If valid, the Async filter will return
# valid video markdown, else, will either scrub the attribute or scrub the HTML.
module GitHub::Goomba
  class VideoTagFilter < NodeFilter
    # Include helpers so we can use EscapeHelper#safe_link_to
    include EscapeHelper
    include ActionView::Helpers::UrlHelper

    include OcticonsHelper

    SELECTOR = Goomba::Selector.new("p,video")

    def selector
      SELECTOR
    end

    def self.cache_key(context)
      replace_link = context[:for_email] || context[:scrub_video] ? "replace_video_with_link" : ""
      [
        *video_host_allowlist,
        replace_link,
      ].reject(&:blank?).join(":")
    end

    def call(node)
      if is_element_node?(node) && node.tag == :p
        process_tag(node)
      elsif is_element_node?(node) && node.tag == :video
        process_video_tag(node)
      else
        node
      end
    end

    def self.enabled?(context)
      repository_context?(context) ||
        organization_context?(context) ||
        gist_context?(context) ||
        draft_issue_context?(context) ||
        wiki_context?(context) ||
        memex_project(context) ||
        saved_reply_context?(context)
    end

    def self.memex_project(context)
      context[:memex_project]&.is_a?(MemexProject)
    end

    def self.wiki_context?(context)
      context.has_key?(:entity) &&
        context[:entity].is_a?(GitHub::Unsullied::Wiki)
    end

    def self.repository_context?(context)
      context.has_key?(:entity) &&
        context[:entity].is_a?(Repository)
    end

    def self.organization_context?(context)
      context.has_key?(:organization) &&
        context[:organization].is_a?(Organization)
    end

    def self.gist_context?(context)
      GitHub::Goomba::Async::SecureAssetsPreSignFilter::GistRelatedContextValidator.is_related_context?(context)
    end

    def self.draft_issue_context?(context)
      context.has_key?(:subject) &&
        context[:subject].is_a?(DraftIssue)
    end

    def self.saved_reply_context?(context)
      (context.has_key?(:subject) && context[:subject]&.is_a?(SavedReply)) ||
      (context.has_key?(:subject_type) && context[:subject_type] == SavedReply.name)
    end

    def self.video_host_allowlist
      GitHub.video_asset_allowlist.compact.map do |u|
        Addressable::URI.parse(u).host || u
      end
    end

    private

    def replace_video_with_link?
      context[:scrub_video] || context[:for_email]
    end

    # Process <video src="githubsource.com/video.mp4"></video> tags.
    def process_video_tag(video_node)
      href = video_node["src"]
      return "" unless href
      return "" unless allowed_video_host?(href)

      if replace_video_with_link?
        # Just return a link, as this context cannot support video tags
        safe_link_to(href, href, rel: "nofollow")
      else
        video_node["gh:video-upload"] = { src: href }.to_json

        nil
      end
    end

    # Process <p><a href="https://user-images.githubusercontent.com/7559041/1234.mp4">…</a></p>
    # tags. A valid video link must be present, on its own line.
    #
    # Returns a <p gh:video-upload='{"src":"https://user-images.githubusercontent.com/7559041/1234.mp4"}'></p>
    # tag if video source is valid, else, returns the original node.
    def process_tag(node)
      link_node, rest = node.children

      return node if replace_video_with_link?
      return node if rest.present? # Video links should only have a link, nothing else
      return node unless is_element_node?(link_node) && link_node.tag == :a

      url = link_node.attributes["href"].to_s
      return unless allowed_video_host?(url)

      node["gh:video-upload"] = { src: url }.to_json

      # Return `nil` as node was modified in place
      nil
    end

    def allowed_video_host?(url)
      uri = Addressable::URI.parse(url)
      self.class.video_host_allowlist.include?(uri.host)
    rescue Addressable::URI::InvalidURIError
      false
    end

  end
end
