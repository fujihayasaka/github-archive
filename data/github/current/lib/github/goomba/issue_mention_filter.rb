# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Matches issue references in user-supplied content one of two formats:
  #
  # 1. As a plain text reference, like github/github#99872.
  #
  # 2. As the target of a link, like <a
  #    href="https://github.com/github/github/issues/99872">…</a>.
  #
  # In both cases, there is a clear and precise way to recover the original
  # input text or node.
  #
  #
  # Plain text references
  # =====================
  #
  # Plain text references are transformed into a tag that looks like this:
  #
  #   <gh:issue-mention nwo="github/github"
  #                     marker="#"
  #                     number="99872"></gh:issue-mention>
  #
  # The 'nwo' is the name-with-owner, the text before the "#". It might be a
  # full nwo (github/github), only an owner (github), or blank, in which case
  # it's omitted from the tag. If only an owner is supplied, it's assumed the
  # reference is to an issue in a repository owned by that owner with the same
  # name as the context repository. If no nwo is supplied at all, it's assumed
  # we are referring to an issue in the context repository.
  #
  # The 'marker' is the character which signals an issue reference. It's usually
  # "#", but for legacy reasons it can be "GH-".  This is always present.
  #
  # The 'number' is the issue or PR number.  This is always present.
  #
  # These are the only attributes that can appear on a <gh:issue-mention> tag,
  # and using them we can reconstitute the exact text that we matched. The
  # capability to do this is necessary if there's no matching issue or PR, in
  # which case we want to restore the text as it was.
  #
  #
  # Link target references
  # ======================
  #
  # Link target references are transformed by adding an attribute to the <a>
  # tag. Given input like this:
  #
  #   <a href="https://github.com/github/github/issues/99872">My issue</a>
  #
  # The following output will be given, ignoring whitespace differences:
  #
  #   <a href="https://github.com/github/github/issues/99872"
  #      gh:issue-mention='{"nwo":"github/github","number":"99872","anchor":null}'>
  #      My issue</a>
  #
  # The tag is unchanged except for having the gh:issue-mention attribute added
  # to it. Because we don't replace the node, but instead modify it in place,
  # other node filters can recurse into its contents and further process them.
  # This concern is unique to link target references, as plain text references,
  # being plain text, cannot contain any other markup that might be recursed
  # into.
  #
  # The 'nwo' element of the JSON object is the full nwo parsed from the URL,
  # and is always present.
  #
  # The 'number' element is likewise parsed from the URL and is always present.
  #
  # The 'anchor' element is present if there's an anchor on the URL, and
  # includes the leading "#" — otherwise it is still present in the object, with
  # a null value. If the link target was
  # "https://github.com/github/github/issues/99872#issuecomment-428066274", the
  # value of the 'anchor' element would be "#issuecomment-428066274".
  #
  # Link targets are of special note because they will result not only when a
  # user enters an explicit link in their comment's Markdown source, but also if
  # they simply paste a GitHub Issue, PR or comment URL into their comment, as
  # it will be autolinked by our Markdown processor. The processing specific to
  # this occurs in GitHub::Goomba::Async::IssueMentionFilter.
  #
  class IssueMentionFilter < NodeFilter
    # Example: github/github, rails
    NAME_OR_NWO = /(?<name_or_nwo>(?:#{GitHub::HTML::IssueMentionFilter::NAME_OR_NWO}))/.freeze

    # Example: "#", "gh-", "/issues/"
    MARKER = %r<(?<marker>#|gh-|/(?:issues|pull|discussions)/)(?=\d)>i.freeze
    NUMBER = /(?<number>\d+)\b/.freeze

    ISSUE_REFERENCE = %r{(?<full_reference>(#{NAME_OR_NWO})?#{MARKER}#{NUMBER})}.freeze

    # whitespace, beginning of line, or some other non-word character must precede the reference.
    # A lookbehind is used so that valid matches for the issue reference have the leader precede
    # them but the leader is not considered part of the match.
    ISSUE_REFERENCE_WITH_LEADER = %r{(?<=(^|\W))#{ISSUE_REFERENCE}}i.freeze

    def initialize(*args)
      super
      @filter = GitHub::HTML::IssueMentionFilter.new("", context, result)
    end

    # selector must be defined, as it's used by the base class, but the selector
    # is also relied on by external classes, so we define it as a class method
    def selector
      self.class.selector
    end

    def self.selector
      Goomba::Selector.new(match: ":text, a[href^='#{GitHub.url}']",
                                    reject: "pre :text, code :text, a :text")
    end

    def self.cache_key(context)
      return unless context[:skip_short_issue_reference]
      "skip_mention_replacement"
    end

    def call(node)
      if is_element_node?(node) # HTML tag
        call_anchor(node) if node.tag == :a
      else # text
        call_text(node)
      end
    end

    private

    def call_anchor(node)
      inner_html = node.inner_html
      return unless node_is_issuish_link?(node)

      text_before = nil
      if (prev_node = node.previous_sibling) && is_text_node?(prev_node)
        text_before = prev_node.text_content
      end

      if md = node["href"].match(GitHub::HTML::IssueMentionFilter.full_url_issue_mention)
        nwo = md[1]
        number = md[2]
        anchor = md[3]

        # Check for the presence of the new `issue` search parameter, this parameter controls
        # whether or not the issue side-panel is open and which issue to load. When included
        # in an issue mention, we want to the rich unfurl to represent the side-panel's issue.
        # This is done within this block as we only want to unfurl the sub-issue in the same
        # scenarios we'd normally unfurl an issue mention.
        begin
          params = Rack::Utils.parse_query(URI(node["href"]).query)
        rescue URI::InvalidURIError
          return
        end

        if params["issue"]
          owner, repository_name, issue_number = params["issue"].split("|")
          nwo = "#{owner}/#{repository_name}" # rubocop:disable GitHub/DoNotAllowLogin owner is display_login from the URL's search params
          number = issue_number

          # anchor is used to determine where the link should go and the trailing text
          # to include in the rich unfurl, i.e. "(comment)" or "(reply in thread)"
          # Explicitly setting this to `nil` ensures no trailing text is added and the
          # user navigates directly to the sub-issue.
          anchor = nil
        end

        node["gh:issue-mention"] = {
          nwo:,
          number:,
          anchor:,
        }.to_json
      elsif md = node["href"].match(GitHub::HTML::IssueMentionFilter.full_url_discussion_mention)
        node["gh:discussion-mention"] = {
          nwo: md[1],
          number: md[2],
          anchor: md[3],
        }.to_json
      # Support for issue sidepanel urls in projects, eg: https://github.com/orgs/github/projects/123/views/1
      elsif node["href"].match(GitHub::HTML::IssueMentionFilter.full_url_project_mention)
        begin
          params = Rack::Utils.parse_query(URI(node["href"]).query)
        rescue URI::InvalidURIError
          return
        end

        if params["issue"]
          owner, repository_name, issue_number = params["issue"].split("|")
          nwo = "#{owner}/#{repository_name}" # rubocop:disable GitHub/DoNotAllowLogin owner is display_login from the URL's search params
          number = issue_number
          anchor = nil
        end

        node["gh:issue-mention"] = {
          nwo:,
          number:,
          anchor:,
        }.to_json
      end

      nil
    end

    # Private: Returns true if the given Goomba node is a link (an `<a>` tag) to a GitHub issue,
    # discussion, the default tab of a pull request, or project sidepanel issue.
    def node_is_issuish_link?(node)
      href = node["href"]
      return false unless is_allowed_url?(href)
      return false if pull_request_tab?(href)
      return false if is_url_with_custom_format?(href)

      Regexp.union(
        GitHub::HTML::IssueMentionFilter.full_url_issue_mention,
        GitHub::HTML::IssueMentionFilter.full_url_discussion_mention,
        GitHub::HTML::IssueMentionFilter.full_url_project_mention
      ) =~ href
    end

    # Private: Returns true if the given URL points to an issue, discussion, pull request, or project.
    def is_allowed_url?(href)
      href =~ %r{/(issues|pull|discussions|projects)/}
    end

    # Private: Returns true if the given URL points to tabs of a pull request.
    def pull_request_tab?(href)
      href =~ GitHub::HTML::IssueMentionFilter::PULL_REQUEST_TABS_REGEX
    end

    # Private: Returns true if the given URL has a custom extension at the end, such as putting
    # `.patch` on the end of a pull request's URL.
    def is_url_with_custom_format?(href)
      href =~ /\.[a-z]+\z/
    end

    # returns an html_safe gh:issue-mention tag
    def issue_mention_tag(nwo, marker, number)
      attrs = {
        nwo: nwo,
        marker: marker,
        number: number,
      }

      ActionController::Base.helpers.content_tag("gh:issue-mention", nil, attrs)
    end

    def call_text(text)
      content = text.html
      return if content !~ GitHub::HTML::IssueMentionFilter::MARKER

      replace_text_mentions(content)
    end

    def replace_text_mentions(html)
      html.gsub!(ISSUE_REFERENCE_WITH_LEADER) do |original|
        match = T.must(Regexp.last_match)
        marker = match[:marker]
        number = match[:number]
        nwo = match[:name_or_nwo] if match.named_captures.keys.include?("name_or_nwo")

        next original if skip_mention_replacement?(nwo, marker, number)

        issue_mention_tag(nwo, marker, number)
      end
    end

    def skip_mention_replacement?(nwo, marker, number)
      return false unless context[:skip_short_issue_reference]
      return true unless nwo.present?
    end
  end
end
