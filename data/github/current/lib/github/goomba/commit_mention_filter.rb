# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class CommitMentionFilter < NodeFilter
    def initialize(*args)
      super
      @filter = GitHub::HTML::CommitMentionFilter.new("", context, result)
    end

    def selector
      Goomba::Selector.new(match: ":text, a[href^='#{GitHub.url}']",
        reject: "pre :text, code :text, a :text")
    end

    def call(node)
      if is_element_node?(node)
        call_anchor(node)
      else
        call_text(node)
      end
    end

    private

    def call_anchor(node)
      text = node.text_content
      href = node["href"]

      # Only shorten autolinked urls
      return unless Addressable::URI.unescape(text) == Addressable::URI.unescape(href)

      # Skip global syntax
      return if text.include?("@")

      params = GitHub::HTML::CommitPathParser.new(href).params
      return unless params

      # See https://github.com/rails/rails/blob/8512213a39b4e1734b844066076dad651103ec74/actionpack/lib/action_dispatch/routing/route_set.rb
      params.each do |key, value|
        if value.is_a?(String)
          value = value.b
          params[key] = URI::DEFAULT_PARSER.unescape(value)
        end
      end

      replace_full_url_commit_mentions(text, href, params) ||
        replace_full_url_compare_mentions(text, href, params)
    end

    # returns an html-safe gh:commit-mention tag
    def commit_mention_tag(nwo, sha, path, autolink: nil)
      attrs = {
        autolink: autolink,
        nwo: nwo,
        path: path,
        sha: sha,
      }.reject { |_k, v| v.blank? }

      ActionController::Base.helpers.content_tag("gh:commit-mention", body = nil, attrs)
    end

    # returns an html-safe gh:compare-mention tag
    def compare_mention_tag(nwo, base, head, fragment, autolink: nil)
      attrs = {
        autolink: autolink,
        base: base,
        fragment: fragment,
        head: head,
        nwo: nwo,
      }.reject { |_k, v| v.nil? }

      ActionController::Base.helpers.content_tag("gh:compare-mention", body = nil, attrs)
    end

    # <a href='/user/project/commit/SHA'>/user/project/commit/SHA</a>  =>
    #   <a href='/user/project/commit/SHA'>user/project@SHA</a>
    # (or possibly)
    #   <a href='/user/project/commit/SHA'>SHA</a>
    # (or even)
    #   <a href='/user/project/commit/SHA'>user@SHA</a>
    #
    # Alternate input is a commit within a PR:
    # <a href='/user/project/pull/123/commits/SHA'>/user/project/pull/123/commits/SHA</a>
    def replace_full_url_commit_mentions(text, url, params)
      # Skip .patch or .diff urls
      return if params[:format]

      sha = if params[:controller] == "commit" && params[:action] == "show"
        params[:name]
      elsif params[:controller] == "pull_requests" && params[:action] == "show" && params[:tab] == "commits"
        params[:range] if params[:range] =~ /\A[0-9a-f]{7,40}\z/
      elsif params[:controller] == "pull_requests" && params[:action] == "commits"
        params[:range] if params[:range] =~ /\A[0-9a-f]{7,40}\z/
      end

      return if !sha

      sha = sha.force_encoding("utf-8").scrub!

      nwo = "#{params[:user_id]}/#{params[:repository]}"

      begin
        uri    = Addressable::URI.parse(url)
        path   = "/#{params[:path]}" if params[:path]
        query  = "?#{uri.query}" if uri.query.present?
        anchor = "##{uri.fragment}" if uri.fragment.present?
        path_text = "#{path}#{query}#{anchor}".force_encoding("utf-8").scrub!
      rescue Addressable::URI::InvalidURIError
        path_text = path
      end

      commit_mention_tag(nwo, sha, path_text, autolink: text)
    end

    # <a href='/user/project/compare/RANGE...RANGE'>/user/project/compare/RANGE...RANGE</a>  =>
    #   <a href='/user/project/compare/RANGE...RANGE'>user/project@RANGE...RANGE</a>
    # (or possibly)
    #   <a href='/user/project/compare/RANGE...RANGE'>RANGE...RANGE</a>
    # (or even)
    #   <a href='/user/project/compare/RANGE...RANGE'>user@RANGE...RANGE</a>
    def replace_full_url_compare_mentions(text, url, params)
      return unless params[:controller] == "compare" && params[:action] == "show"

      # Skip .patch or .diff urls
      return if params[:range] =~ /\.(diff|patch)\z/

      nwo   = "#{params[:user_id]}/#{params[:repository]}"
      range = params[:range]

      points = range.split("...")
      return unless points.length == 2

      begin
        uri = Addressable::URI.parse(url)
      rescue Addressable::URI::InvalidURIError
        return
      end
      return unless uri.query.blank?

      anchor = "##{uri.fragment}" if uri.fragment.present?
      compare_mention_tag(
        nwo,
        Addressable::URI.encode_component(points[0], Addressable::URI::CharacterClasses::PATH),
        Addressable::URI.encode_component(points[1], Addressable::URI::CharacterClasses::PATH),
        anchor,
        autolink: url
      )
    end

    def call_text(text)
      html = text.html
      return unless html.include?("@") || html =~ /[0-9a-f]{7,40}\b/

      if @filter.can_access_repo?(repository)
        replace_contextual_mentions(html)
      else
        replace_global_commit_mentions(html)
      end
    end

    CONTEXTUAL_PATTERN = Regexp.union(
      GitHub::HTML::CommitMentionFilter::BARE_RANGE_PATTERN,
      GitHub::HTML::CommitMentionFilter::REPO_COMMIT_PATTERN,
      GitHub::HTML::CommitMentionFilter::BARE_COMMIT_PATTERN,
    )
    def replace_contextual_mentions(html)
      html.gsub!(CONTEXTUAL_PATTERN) do |_original|
        match = T.must(Regexp.last_match)

        case
        when match[1]
          leader, range = match[1], match[2]
          shas = T.must(range).split(/\.\.\./)
          EscapeHelper.safe_join([leader, compare_mention_tag(nil, shas[0], shas[1], nil)])

        when match[3]
          leader, name, sha = match[3], match[4], match[5]
          EscapeHelper.safe_join([leader, commit_mention_tag(name, sha, nil)])

        when match[6]
          leader, sha = match[6], match[7]
          EscapeHelper.safe_join([leader, commit_mention_tag(nil, sha, nil)])
        end
      end
    end

    # user/repo@SHA =>
    #   <a href='/user/repo/commit/SHA'>user/repo@SHA</a>
    def replace_global_commit_mentions(text)
      text.gsub!(GitHub::HTML::CommitMentionFilter::GLOBAL_COMMIT_PATTERN) do |_match|
        leader, nwo, sha = $1, $2, $3
        EscapeHelper.safe_join([leader, commit_mention_tag(nwo, sha, nil)])
      end
    end
  end
end
