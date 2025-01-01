# typed: true
# frozen_string_literal: true

module GitHub::HTML
  # Sugar for linking to commit SHA's. The following syntaxes are
  # supported where SHA is a 7-40 char hex String.
  #
  # When :entity is provided in the context:
  #   SHA (7-40 char)
  #   user@SHA
  #   user/project@SHA
  #
  # When no :entity is provided in the context:
  #   user/project@SHA
  #
  # Context options:
  #   :base_url - Used to construct commit URLs.
  #   :entity   - Used to determine current context for bare SHA1 references.
  class CommitMentionFilter < Filter
    attr_accessor :valid_shas

    def self.cache_key(context)
      return unless context[:expanded_shas]
      context[:expanded_shas].to_s
    end

    def call
      commit_mentions.clear

      populate_valid_sha_cache

      apply_link_filter :replace_full_url_commit_mentions
      apply_link_filter :replace_full_url_compare_mentions

      if can_access_repo?(repository)
        apply_filter :replace_bare_range_mentions
        apply_filter :replace_repo_commit_mentions
        apply_filter :replace_bare_commit_mentions
      else
        apply_filter :replace_global_commit_mentions
      end

      arrayify_commit_mentions

      doc
    end

    def apply_filter(method_name)
      doc.xpath(".//text()").each do |node|
        content = node.to_html
        next unless content.include?("@") || content =~ /[0-9a-f]{7,40}\b/
        next if has_ancestor?(node, %w(pre code a))
        html = send(method_name, content)
        node.replace(html) if html
      end
    end

    def populate_valid_sha_cache
      @valid_shas = context[:expanded_shas] || populate_valid_sha_cache!
    end

    def populate_valid_sha_cache!
      return {} unless repository

      potential_shas = doc.xpath(".//text()").flat_map do |node|
        node.to_html.scan(/\b[0-9a-f]{7,40}\b/)
      end.uniq

      return {} if potential_shas.empty?

      repository.expand_oids(potential_shas, "commit")
    rescue GitRPC::Error, SpokesAPI::Error
      {}
    end

    # user/repo@SHA =>
    #   <a href='/user/repo/commit/SHA'>user/repo@SHA</a>
    GLOBAL_COMMIT_PATTERN = /(^|\s|[({\[])([\w-]+\/[\w.-]+)@([0-9a-f]{7,40})\b/
    def replace_global_commit_mentions(text)
      text.gsub!(GLOBAL_COMMIT_PATTERN) do |_match|
        leader, nwo, sha = $1, $2, $3

        # to deal with renamed repos
        repo = find_repository(nwo)
        nwo  = repo.name_with_display_owner if repo

        text = "#{nwo}@<tt>#{GitHub::HTML::CommitMentionFilter.trimmed_commit_sha(sha)}</tt>"
        "#{leader}<a href='#{commit_url(nwo, sha)}' class='commit-link'>#{text}</a>"
      end
    end

    # user/repo@SHA =>
    #   <a href='/user/repo/commit/SHA'>user/repo@SHA</a>
    # user@SHA =>
    #   <a href='/user/repo/commit/SHA'>user@SHA</a>
    REPO_COMMIT_PATTERN = /(^|[\s({\[])([\w.\/-]+)?@([0-9a-f]{7,40})\b/
    NWO_OR_USER_PATTERN = /\A[\w-]+\/?[\w.-]*\z/
    def replace_repo_commit_mentions(text)
      text.gsub!(REPO_COMMIT_PATTERN) do |original|
        leader, name, sha = $1, $2, $3

        if name && !name.match(NWO_OR_USER_PATTERN)
          next original
        end

        # to deal with renamed repos
        repo = find_repository(name)
        if repo && name
          name = name["/"] ? repo.name_with_display_owner : repo.owner_display_login
        end

        url  = [repo_url(name), "commit", sha].join("/")
        text = "#{name}@<tt>#{GitHub::HTML::CommitMentionFilter.trimmed_commit_sha(sha)}</tt>"
        "#{leader}<a href='#{url}' class='commit-link'>#{text}</a>"
      end
    end

    # SHA =>
    #   <a href='/user/repo/commit/SHA'>SHA</a>
    BARE_COMMIT_PATTERN = /(^|\.{2,3}|[({@\s\[])([0-9a-f]{7,40})\b/
    def replace_bare_commit_mentions(text)
      replaced = T.let(false, T::Boolean)
      text.gsub!(BARE_COMMIT_PATTERN) do |match|
        leader, sha = $1, $2

        if reference = commit_reference(sha)
          # link is to expanded SHA1
          url = [repo_url, "commit", reference.sha].join("/")
          replaced = true
          "#{leader}<a href='#{url}' class='commit-link'><tt>#{reference.short_sha}</tt></a>"
        else
          match
        end
      end
      replaced ? text : nil
    end

    # SHA...SHA =>
    #   <a href='/user/repo/compare/RANGE'>RANGE</a>
    BARE_RANGE_PATTERN = /(^|[({@\s\[])([0-9a-f]{7,40}\.\.\.[0-9a-f]{7,40})\b/
    def replace_bare_range_mentions(text)
      replaced = T.let(false, T::Boolean)
      text.gsub!(BARE_RANGE_PATTERN) do |match|
        leader, range = $1, $2
        url = [repo_url, "compare", range].join("/")

        shas = range.split(/(\.\.\.)/)
        oper = shas.slice!(1, 1).first
        refs = shas.collect { |sha|  commit_reference(sha) }

        if refs.all?
          range = refs.collect(&:short_sha).join(oper)
          replaced = true
          "#{leader}<a href='#{url}' class='commit-link'><tt>#{range}</tt></a>"
        else
          match
        end
      end
      replaced ? text : nil
    end

    def apply_link_filter(method_name)
      doc.search("a[href^='#{GitHub.url}']").each do |node|
        text = node.text
        href = node.attributes["href"].value

        # Only shorten autolinked urls
        next unless Addressable::URI.unescape(text) == Addressable::URI.unescape(href)

        # Skip global syntax
        next if text.include?("@")

        html = apply_link_filter_html(method_name, text, href)

        node.replace(html) if html
      end
    end

    def apply_link_filter_html(method_name, text, href)
      params = CommitPathParser.new(href).params
      return unless params

      send(method_name, text, href, params)
    end

    # <a href='/user/project/commit/SHA'>/user/project/commit/SHA</a>  =>
    #   <a href='/user/project/commit/SHA'>user/project@SHA</a>
    # (or possibly)
    #   <a href='/user/project/commit/SHA'>SHA</a>
    # (or even)
    #   <a href='/user/project/commit/SHA'>user@SHA</a>
    def replace_full_url_commit_mentions(text, url, params)
      sha = if params[:controller] == "commit" && params[:action] == "show"
        params[:name]
      elsif params[:controller] == "pull_requests" && params[:action] == "show" && params[:tab] == "commits"
        params[:range] if params[:range] =~ /\A[0-9a-f]{7,40}\z/
      elsif params[:controller] == "pull_requests" && params[:action] == "commits"
        params[:range] if params[:range] =~ /\A[0-9a-f]{7,40}\z/
      end

      if sha
        nwo = "#{params[:user_id]}/#{params[:repository]}"

        # Skip .patch or .diff urls
        return if params[:format]

        # Skip if there's no sha to convert
        return if sha.nil?

        # to deal with renamed repos
        old_nwo = nwo
        repo = find_repository(nwo)
        nwo  = repo.name_with_display_owner if repo
        url  = url.sub("/#{old_nwo}", "/#{nwo}")

        begin
          uri    = Addressable::URI.parse(url)
          path   = "/#{params[:path]}" if params[:path]
          query  = "?#{uri.query}" if uri.query.present?
          anchor = "##{uri.fragment}" if uri.fragment.present?
          path_text = "#{path}#{query}#{anchor}"
        rescue Addressable::URI::InvalidURIError
          path_text = path
        end

        Nokogiri::HTML::Builder.new do |doc|
          doc.a(href: url, class: "commit-link") do
            doc.text(repo_text(nwo))
            doc.tt { doc.text(GitHub::HTML::CommitMentionFilter.trimmed_commit_sha(sha)) }
            doc.text(path_text)
          end
        end.to_html.gsub("\n", "")
      end
    end

    # <a href='/user/project/compare/RANGE...RANGE'>/user/project/compare/RANGE...RANGE</a>  =>
    #   <a href='/user/project/compare/RANGE...RANGE'>user/project@RANGE...RANGE</a>
    # (or possibly)
    #   <a href='/user/project/compare/RANGE...RANGE'>RANGE...RANGE</a>
    # (or even)
    #   <a href='/user/project/compare/RANGE...RANGE'>user@RANGE...RANGE</a>
    def replace_full_url_compare_mentions(text, url, params)
      if params[:controller] == "compare" && params[:action] == "show"
        nwo   = "#{params[:user_id]}/#{params[:repository]}"
        range = params[:range]

        # Skip .patch or .diff urls
        return if params[:range] =~ /\.(diff|patch)$/

        points = range.split("...")
        return unless points.length == 2

        # to deal with renamed repos
        old_nwo = nwo
        repo = find_repository(nwo)
        nwo  = repo.name_with_display_owner if repo
        url  = url.sub("/#{old_nwo}", "/#{nwo}")

        begin
          uri = Addressable::URI.parse(url)
        rescue Addressable::URI::InvalidURIError
          return
        end
        return unless uri.query.blank?

        points.map! do |point|
          if point =~ /\A[0-9a-f]{7,40}([~^].*)?\z/
            "#{point[0, 7]}#{$1}"
          else
            point
          end
        end
        anchor = "##{uri.fragment}" if uri.fragment

        Nokogiri::HTML::Builder.new do |doc|
          doc.a(href: url, class: "commit-link") do
            doc.text(repo_text(nwo))
            doc.tt { doc.text(points.join("...")) }
            doc.text(anchor)
          end
        end.to_html.gsub("\n", "")
      end
    end

    # Get repo text for a given nwo
    # see Filter#repo_text
    # redefined here for possible '@' inclusion
    def repo_text(nwo)
      text  = super(nwo)
      text += "@" unless text.blank?
      text
    end

    # List of commits referenced.
    #
    # Returns a list CommitReference objects.
    # see the arrayification, below
    def commit_mentions
      result[:commits] ||= Hash.new
    end

    # Internal: turn the stored commit_mentions into an array for use
    # outside this class
    def arrayify_commit_mentions
      result[:commits] = commit_mentions.values.compact
    end

    # Create a CommitReference object that store a referenced commit and
    # repository it belongs to and appends it to the list of mentioned commits
    # stored in the context at commit_mentions. There is a 10 mentions limit,
    # after which they are ignored.
    #
    # sha - the String SHA1 of the referenced commit.
    #
    # Returns a CommitReference object. If the SHA1 doesn't exists on the
    #   repository, the reference's commit attribute returns a FakeCommit
    #   instead of a real Commit.
    def commit_reference(sha)
      sha = sha.downcase
      if full_oid = @valid_shas[sha]
        commit_mentions[sha] = CommitReference.new(repository, full_oid, GitHub::HTML::CommitMentionFilter.trimmed_commit_sha(full_oid))
      end
    end

    CommitReference = Struct.new(:repository, :sha, :short_sha)

    def repo_url(name = nil)
      if name.blank?
        [base_url.chomp("/"), repository.name_with_display_owner].join("/")
      elsif name.include?("/")
        [base_url.chomp("/"), name].join("/")
      else
        # user@SHA - assume same repo name but different user
        [base_url.chomp("/"), name, repository.name].join("/")
      end
    end

    def commit_url(nwo, commit_id)
      [base_url.chomp("/"), nwo, "commit", commit_id].join("/")
    end

    # A heuristic to determine to trim the SHA if necessary.
    # If it is >= 30 characters and all hex we will trim.
    # This is to fix trimming names that should not be, such as "monorepo",
    # Originially reported here: https://github.com/github/issues/issues/2135
    def self.trimmed_commit_sha(sha)
      return sha unless sha.length >= 30
      return sha unless sha =~ /\A[0-9a-f]+\z/
      sha[0, 7]
    end
  end
end
