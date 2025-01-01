# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class IssueBlobFilter < NodeFilter
    COMMIT_OID_REGEX = /\A[a-f0-9]{40}\z/.freeze
    RANGE_REGEX = /\A(L(?<range_start>\d+)-)?L(?<range_end>\d+)\z/.freeze

    def selector
      Goomba::Selector.new(match: "a[href^='#{GitHub.url}']")
    end

    def permalink_template
      Addressable::Template.new("#{GitHub.url}/{owner}/{repo}/blob/{commit_oid}/{+filepath}{?query*}{#fragment}")
    end

    def call(node)
      return unless repository

      inner_html = node.inner_html
      return unless node["href"] == inner_html

      href = node["href"].b

      begin
        if md = permalink_template.match(href)
          # TODO: Properly support renamed repos here
          return unless repository.name_with_display_owner == "#{md[:owner]}/#{md[:repo]}"
          return unless md[:commit_oid] =~ COMMIT_OID_REGEX
          return unless range = md[:fragment]&.match(RANGE_REGEX)
          # Handle potentially missing filepaths
          # https://github.com/github/pull-requests/issues/11107#issue-2195634181
          return unless md[:filepath]

          blob_mention_tag(
            filepath: md[:filepath],
            commit_oid: md[:commit_oid],
            range_start: range[:range_start] || range[:range_end],
            range_end: range[:range_end],
            permalink: href,
            text: inner_html,
          )
        end
      rescue Addressable::URI::InvalidURIError
        # URL was invalid, so we can't parse it
      end
    end

    def self.enabled?(context)
      return false if context[:hide_code_blobs]
      !context[:for_email]
    end

    # returns an html-safe gh:blob-mention tag
    def blob_mention_tag(filepath:, commit_oid:, range_start:, range_end:, permalink:, text:)
      attrs = {
        commit_oid: commit_oid,
        filepath: filepath,
        permalink: permalink,
        range_start: range_start,
        range_end: range_end,
        text: text,
      }.reject { |_k, v| v.nil? }

      # passing nil for body ensures the closing tag remains
      ActionController::Base.helpers.content_tag("gh:blob-mention", nil, attrs)
    end
  end
end
