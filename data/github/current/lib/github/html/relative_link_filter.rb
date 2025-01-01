# typed: true
# frozen_string_literal: true

module GitHub::HTML
  # Relative link filter modifies relative links in markdown based on viewing
  # location, making it so these links lead to the correct desination whether
  # viewed locally, as a blob, or (in the case of a README), as part of a tree
  # view.
  #
  # Requires values passed in the context:
  #
  # entity     - must be a repository; skips otherwise
  # path       - path where this markdown content is being shown
  #              (e.g. "README.md", "nested/dir", or "")
  # committish - committish for this markdown content
  #              (branch name, ref name, commit oid)
  # view       - view where this markdown content is being shown
  #              (viz. :tree, :blob, :preview)
  class RelativeLinkFilter < Filter
    def self.cache_key(context)
      keys = [
        context[:committish].try(:b),
        context[:view],
        context[:path].try(:b),
        context[:entity].try(:name_with_owner),
      ].reject(&:blank?).join(":")
    end

    def call
      return doc unless should_process?

      doc.search("a").each do |node|
        apply_filter node, "href"
      end
      doc.search("img").each do |node|
        apply_filter node, "src"
      end

      doc
    end

    def should_process?
      repository && context[:path]
    end

    def apply_filter(node, attribute)
      new_url = make_relative(node.attributes[attribute].try(:value))
      return unless new_url
      node.attributes[attribute].value = new_url
    end

    def make_relative(url)
      return unless url

      return if url.match(%r{^[a-z][a-z0-9\+\.\-]+:}i)  # RFC 3986 <3 U
      return if url.match(%r{^//})
      return if url.match(/^#/)

      new_url = corrected_link(url)
      new_url = absolute_link(new_url) if context[:absolute_path] || context[:for_email]
      return if new_url == url
      new_url
    end

    private

    def root?(href)
      href.starts_with?("/")
    end

    def tree_view?
      context[:view] == :tree
    end

    def org_profile_view?
      context[:view] == :org_profile
    end

    # Return only the directory part of the path
    #   (removing the end if it"s a blob)
    #
    # Returns nil if there is no directory part
    def corrected_path
      path = context[:path]
      path = File.dirname(path) unless tree_view? || org_profile_view?
      return if path == "."
      # Path is a binary string, so URL-escape each one of its components
      # to ensure that we can display it as a valid UTF8 string on the
      # view _and_ that the resulting link still works
      path.split("/").map { |p| UrlHelper.escape_path(p) }.join("/")
    end

    # Build a more absolute relative link
    #
    # path   - path for current location
    # link   - original link
    #
    # / nwo / action / committish / path / link
    def corrected_link(link)
      path = root?(link) ? nil : corrected_path
      link.sub!(%r{^/?}, "")

      parts = [
        repository.name_with_display_owner,
        "blob",
        UrlHelper.escape_branch(context[:committish]),
        path,
        link,
      ].delete_if(&:blank?)

      File.expand_path("/" + parts.join("/"))
    end

    # Build an absolute link with the scheme and hostname
    #
    # link - the corrected path or link
    #
    # GitHub.url / nwo / action / committish / path / link
    def absolute_link(link)
      GitHub.url + link
    end
  end
end
