# typed: true
# frozen_string_literal: true

module GitHub::HTML
  # Sugar for linking to issues, pull requests, and discussions.
  #
  # When :repository is provided in the context:
  #   #num
  #   user#num
  #   user/project#num
  #
  # When no :repository is provided in the context:
  #   user/project#num
  #
  # Context options:
  #   :base_url   - Used to construct URLs.
  #   :repository - Used to determine current context for bare number references.
  #
  # This filter writes information to the result hash:
  #   :issues      - An array of IssueReference objects for each issue or pull request
  #                  mentioned. You can use IssueReference#close? to determine if the
  #                  reference was prefixed with (close[sd]|fixe[sd]).
  #   :discussions - An array of DiscussionReference objects for each discussion
  #                  mentioned.
  class IssueMentionFilter < Filter
    extend T::Sig

    DISCUSSION_COMMENT_DOM_ID_PREFIX = "discussioncomment-"
    DISCUSSION_COMMENT_REGEX = /#{DISCUSSION_COMMENT_DOM_ID_PREFIX}(\d+)/
    PULL_REQUEST_TABS_REGEX = %r{/\d+/(files|commits|conflicts|checks)}

    def self.cache_key(context)
      return unless context[:disable_hovercard_attributes]
      "skip_hovercard"
    end

    def call
      apply_full_url_issue_mentions_filter
      apply_full_url_discussion_mentions_filter

      if can_access_repo?(repository)
        apply_filter :replace_repo_issue_mentions
        apply_filter :replace_repo_discussion_mentions
        apply_filter :replace_bare_issue_mentions
        apply_filter :replace_bare_discussion_mentions
      else
        apply_filter :replace_global_issue_mentions
        apply_filter :replace_global_discussion_mentions
      end

      doc
    end

    # once upon a time, we used gh-NUM to mark issues
    # and we care about historical compatibility
    MARKER = %r<(?:#|gh-|/(?:issues|pull|discussions)/)(?=\d)>i

    def apply_filter(method_name)
      doc.xpath(".//text()").each do |node|
        content = node.to_html
        next if content !~ MARKER                        # perf
        next if has_ancestor?(node, %w(pre code a))      # <-- slow
        html = send(method_name, content)
        node.replace(html) if html
      end
    end

    LEADER      = /(^|\s|[(\[{:])/
    NWO         = /(\w+(?:-\w+)*\/[.\w-]+)/
    NAME_OR_NWO = /(\w+(?:-\w+)*(?:\/[.\w-]+)?)/
    NUMBER      = /(\d+)\b/

    GLOBAL_ISSUE_MENTIONS = %r<#{LEADER}#{NWO}#{MARKER}#{NUMBER}>

    # user/project#num =>
    #   <a href='/user/project/issues/num'>user/project#num</a>
    # user/project/issues/num =>
    #   <a href='/user/project/issues/num'>user/project#num</a>
    # user/project/pull/num =>
    #   <a href='/user/project/issues/num'>user/project#num</a>
    def replace_global_issue_mentions(text)
      replaced = T.let(false, T::Boolean)
      text.gsub!(GLOBAL_ISSUE_MENTIONS) do |match|
        leader, nwo, number = $1, $2, $3.to_i

        if reference = issue_reference(nil, number, nwo)
          nwo     = reference.issue.repository.name_with_display_owner  # to deal with renamed repos
          content = "#{nwo}##{number}"
          url     = reference.issue.url

          replaced = true
          issue_link(url, content, before: leader, issue: reference.issue)
        else
          match
        end
      end
      replaced ? text : nil
    end

    # user/project#num =>
    #   <a href='/user/project/discussions/num'>user/project#num</a>
    # user/project/discussions/num =>
    #   <a href='/user/project/discussions/num'>user/project#num</a>
    def replace_global_discussion_mentions(text)
      replaced = T.let(false, T::Boolean)
      text.gsub!(GLOBAL_ISSUE_MENTIONS) do |match|
        leader, nwo, number = $1, $2, $3.to_i

        if reference = discussion_reference(number, nwo)
          nwo     = reference.discussion.repository.name_with_owner  # to deal with renamed repos
          content = "#{nwo}##{number}"
          url     = reference.discussion.url

          replaced = true
          discussion_link(url, content, before: leader, discussion: reference.discussion)
        else
          match
        end
      end
      replaced ? text : nil
    end

    # user/project#num =>
    #   <a href='/user/project/issues/num'>user/project#num</a>
    # user#num =>
    #   <a href='/user/project/issues/num'>user#num</a>
    # user/project/issues/num =>
    #   <a href='/user/project/issues/num'>user/project#num</a>
    # user/project/pull/num =>
    #   <a href='/user/project/issues/num'>user/project#num</a>
    REPO_ISSUE_REFERENCE = %r<#{LEADER}#{NAME_OR_NWO}#{MARKER}#{NUMBER}>
    def replace_repo_issue_mentions(text)
      replaced = T.let(false, T::Boolean)
      text.gsub!(REPO_ISSUE_REFERENCE) do |match|
        leader, nwo, number = $1, $2, $3.to_i
        word = self.class.close_text($`)

        if reference = issue_reference(word, number, nwo)
          # to deal with renamed repos
          repo  = reference.issue.repository
          nwo   = nwo["/"] ? repo.name_with_display_owner : repo.owner_display_login

          content = "#{nwo}##{number}"
          url     = reference.issue.url

          replaced = true
          issue_link(url, content, before: leader, issue: reference.issue)
        else
          match
        end
      end
      replaced ? text : nil
    end

    # user/project#num =>
    #   <a href='/user/project/discussions/num'>user/project#num</a>
    # user#num =>
    #   <a href='/user/project/discussions/num'>user#num</a>
    # user/project/discussions/num =>
    #   <a href='/user/project/discussions/num'>user/project#num</a>
    def replace_repo_discussion_mentions(text)
      replaced = T.let(false, T::Boolean)
      text.gsub!(REPO_ISSUE_REFERENCE) do |match|
        leader, nwo, number = $1, $2, $3.to_i

        if reference = discussion_reference(number, nwo)
          # to deal with renamed repos
          repo  = reference.discussion.repository
          nwo   = nwo["/"] ? repo.name_with_owner : repo.owner.login

          content = "#{nwo}##{number}"
          url     = reference.discussion.url

          replaced = true
          discussion_link(url, content, before: leader, discussion: reference.discussion)
        else
          match
        end
      end
      replaced ? text : nil
    end

    CLOSE_WORD_AND_SUFFIX = /\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)(?:\s+|\s*:\s*)/i
    DUPLICATE_WORD_AND_SUFFIX = /\b(?:duplicate of)(?:\s+|\s*:\s*)/i
    CLOSE_LEADER = /(^|#{CLOSE_WORD_AND_SUFFIX}|\s|\W)/i
    KEYWORD_LEADER = /(^|#{CLOSE_WORD_AND_SUFFIX}|#{DUPLICATE_WORD_AND_SUFFIX}|\s|\W)/i

    # #num =>
    #   <a href='/user/project/issues/num'>#num</a>
    KEYWORD_ISSUE_REFERENCE = /#{KEYWORD_LEADER}(gh-|#)#{NUMBER}/i
    def replace_bare_issue_mentions(text)
      replaced = T.let(false, T::Boolean)
      text.gsub!(KEYWORD_ISSUE_REFERENCE) do |match|
        word, pound, number = $1, $2, $3.to_i

        if reference = issue_reference(word, number)
          issue = reference.issue

          replaced = true
          issue_link(issue.url, "#{pound}#{number}", before: word, issue: issue)
        else
          match
        end
      end
      replaced ? text : nil
    end

    # #num =>
    #   <a href='/user/project/discussions/num'>#num</a>
    def replace_bare_discussion_mentions(text)
      replaced = T.let(false, T::Boolean)
      text.gsub!(KEYWORD_ISSUE_REFERENCE) do |match|
        word, pound, number = $1, $2, $3.to_i

        if reference = discussion_reference(number)
          discussion = reference.discussion

          replaced = true
          discussion_link(discussion.url, "#{pound}#{number}", before: word,
            discussion: discussion)
        else
          match
        end
      end
      replaced ? text : nil
    end

    def apply_full_url_issue_mentions_filter
      doc.search("a[href^='#{GitHub.url}']").each do |node|
        text = node.text
        href = node.attributes["href"].value

        next unless href =~ %r{/(issues|pull)/}
        next if href =~ PULL_REQUEST_TABS_REGEX
        next if href =~ /\.[a-z]+\z/

        text_before = nil
        if (before = node.previous) && before.text?
          text_before = before.text
        end

        html = replace_full_url_issue_mentions(text, href, text_before)
        node.replace(html) if html
      end
    end

    def apply_full_url_discussion_mentions_filter
      doc.search("a[href^='#{GitHub.url}']").each do |node|
        text = node.text
        href = node.attributes["href"].value

        next unless href =~ %r{/discussions/}
        next if href =~ PULL_REQUEST_TABS_REGEX
        next if href =~ /\.[a-z]+\z/

        text_before = nil
        if (before = node.previous) && before.text?
          text_before = before.text
        end

        html = replace_full_url_discussion_mentions(text, href, text_before)
        node.replace(html) if html
      end
    end

    def self.full_url_issue_mention
      %r<#{Regexp.escape(GitHub.url)}/#{NWO}/(?:issues|pull)/(\d+)(#[\w-]+)?\b>
    end

    # <a href='/user/project/issues/num'>/user/project/issues/num</a>  =>
    #   <a href='/user/project/issues/num'>user/project#num</a>
    # <a href='/user/project/pull/num'>/user/project/pull/num</a>  =>
    #   <a href='/user/project/issues/num'>user/project#num</a>
    # (or possibly)
    #   <a href='/user/project/issues/num'>#num</a>
    # (or even)
    #   <a href='/user/project/issues/num'>user#num</a>
    def replace_full_url_issue_mentions(text, href, text_before)
      md = href.match(self.class.full_url_issue_mention)
      if md
        nwo    = md[1]
        number = md[2].to_i
        anchor = md[3] || ""

        word = self.class.close_text(text_before)

        if reference = issue_reference(word, number, nwo)
          return unless text == href

          nwo  = reference.issue.repository.name_with_display_owner  # to deal with renamed repos
          repo = repo_text(nwo)

          text   = "#{repo}##{number}#{anchor_text(anchor)}"
          url    = reference.issue.url + anchor
          suffix = ""
          if url != href && (index = href.index(url))
            # Restore trailing punctuation that was gobbled as part of the URL
            suffix = href[index + url.length...href.length]
          end

          issue_link(url, text, issue: reference.issue, anchor: anchor) + suffix
        end
      end
    end

    def self.full_url_discussion_mention
      %r<#{Regexp.escape(GitHub.url)}/#{NWO}/(?:discussions)/(\d+)(#[\w-]+)?\b>
    end

    # <a href='/user/project/discussions/num'>/user/project/discussions/num</a>  =>
    #   <a href='/user/project/discussions/num'>user/project#num</a>
    # (or possibly)
    #   <a href='/user/project/discussions/num'>#num</a>
    # (or even)
    #   <a href='/user/project/discussions/num'>user#num</a>
    def replace_full_url_discussion_mentions(text, href, text_before)
      md = href.match(self.class.full_url_discussion_mention)
      if md
        nwo    = md[1]
        number = md[2].to_i
        anchor = md[3] || ""

        if reference = discussion_reference(number, nwo)
          return unless text == href

          nwo  = reference.discussion.repository.name_with_owner  # to deal with renamed repos
          repo = repo_text(nwo)

          threaded = self.class.references_threaded_discussion_comment?(reference.discussion, anchor)

          text   = "#{repo}##{number}#{anchor_text(anchor, threaded: threaded)}"
          url    = reference.discussion.url + anchor

          suffix = ""
          if url != href && (index = href.index(url))
            # Restore trailing punctuation that was gobbled as part of the URL
            suffix = href[index + url.length...href.length]
          end

          discussion_link(url, text, discussion: reference.discussion, anchor: anchor) + suffix
        end
      end
    end

    PERMISSION_TEXT = "Title is private".freeze
    ERROR_TEXT = "Failed to load title".freeze

    # Create an issue link
    #
    # url    - target URL for the link
    # text   - text to be linked
    # before - optional text to put before the link
    # issue  - the Issue being linked
    # anchor - the part of the URL after the hash, if any
    #
    # Returns an html-safe String link (a href) tag
    def issue_link(url, text, before: "", issue:, anchor: nil)
      attrs = {
        "class" => "issue-link js-issue-link",
        "data-error-text" => ERROR_TEXT,
        "data-id" => issue.id,
        "data-permission-text" => PERMISSION_TEXT,

        # Issue#url will go to /pull/ if the issue is a PR.
        # It's easier if this always goes to one action.
        "data-url" => "#{issue.repository.permalink}/issues/#{issue.number}",
      }.merge(data: issue_hovercard_data_attributes(issue, anchor: anchor))

      link = ActionController::Base.helpers.link_to(text, url, attrs)
      EscapeHelper.safe_join([before, link])
    end

    # Create a discussion link
    #
    # url    - target URL for the link
    # text   - text to be linked
    # before - optional text to put before the link
    # discussion - the Discussion being linked
    # anchor - the part of the URL after the hash, if any
    #
    # Returns an html-safe String link (a href) tag
    def discussion_link(url, text, before: "", discussion:, anchor: nil)
      attrs = {
        "class" => "issue-link js-issue-link",
        "data-error-text" => ERROR_TEXT,
        "data-id" => discussion.id,
        "data-permission-text" => PERMISSION_TEXT,
        "data-url" => "#{discussion.repository.permalink}/discussions/#{discussion.number}",
      }.merge(data: discussion_hovercard_data_attributes(discussion, anchor: anchor))

      link = ActionController::Base.helpers.link_to(text, url, attrs)
      EscapeHelper.safe_join([before, link])
    end

    # Internal: Translate anchor to explanatory text
    #
    # anchor - the anchor on the page
    # threaded - boolean representing whether or not the anchor refers to a
    #            comment that's nested under another comment
    #
    # Returns String
    def anchor_text(anchor, threaded: nil)
      return if anchor.blank?

      text = case anchor
      when /discussion-diff-/
        "diff"
      when /commits-pushed-/
        "commits"
      when /ref-/
        "reference"
      when /pullrequestreview/
        "review"
      when /#{DISCUSSION_COMMENT_DOM_ID_PREFIX}/
        threaded ? "reply in thread" : "comment"
      else
        "comment"
      end

      " (#{text})"
    end

    ISSUE_COMMENT_ANCHOR_REGEX = /\A#?issuecomment-(?<comment_id>\d+)\z/
    PR_REVIEW_COMMENT_ANCHOR_REGEX = /\A#?discussion_r(?<comment_id>\d+)\z/
    PR_REVIEW_ANCHOR_REGEX = /\A#?pullrequestreview-(?<comment_id>\d+)\z/
    DISCUSSION_COMMENT_ANCHOR_REGEX = /\A#?#{DISCUSSION_COMMENT_DOM_ID_PREFIX}(?<comment_id>\d+)\z/

    # Returns an IssueComment, PullRequestReviewComment, or PullRequestReview database ID
    # from a given anchor from a URL.
    #
    # anchor - String; e.g., issuecomment-123, discussion_r123, pullrequestreview-123
    #
    # Returns either an empty array or an array with the comment ID and the comment type.
    def self.comment_id_and_type_from(anchor)
      return [] if anchor.blank?

      match_data = anchor.match(ISSUE_COMMENT_ANCHOR_REGEX)
      if match_data
        id = match_data[:comment_id]
        type = IssueOrPullRequestHovercard::ISSUE_COMMENT_TYPE
        return [id, type]
      end

      match_data = anchor.match(PR_REVIEW_COMMENT_ANCHOR_REGEX)
      if match_data
        id = match_data[:comment_id]
        type = IssueOrPullRequestHovercard::REVIEW_COMMENT_TYPE
        return [id, type]
      end

      match_data = anchor.match(PR_REVIEW_ANCHOR_REGEX)
      if match_data
        id = match_data[:comment_id]
        type = IssueOrPullRequestHovercard::REVIEW_TYPE
        return [id, type]
      end

      match_data = anchor.match(DISCUSSION_COMMENT_ANCHOR_REGEX)
      if match_data
        id = match_data[:comment_id]
        type = nil # only one type of comment on a discussion, so don't need to distinguish
        return [id, type]
      end

      []
    end

    # Array of IssueReference objects written to the result hash so that
    # callers can find referenced issues.
    def issue_mentions
      result[:issues] ||= []
    end

    # Array of DiscussionReference objects written to the result hash so that
    # callers can find referenced discussions.
    def discussion_mentions
      result[:discussions] ||= []
    end

    # Create an IssueReference for the given issue/PR number and save it in the
    # result hash's :issue_mentions value.
    #
    # word   - The leading text before the issue number. Used to mark the
    #          IssueReference as closed or not.
    # number - The issue/PR number as an integer.
    # repo   - The Repository object where the issuish object should be searched for. May
    #          also be a string '<user>/<repo>' value.
    #
    # Returns an IssueReference when the mention is valid, or nil when the
    # issueish record could not be found.
    def issue_reference(word, number, repo = nil)
      repository = find_repository(repo)
      return unless can_access_repo?(repository)

      issuish = T.let(nil, T.nilable(Issue))

      # first try to find the issue/PR in the current or explicitly
      # referenced repository
      issuish = get_referenced_issue(repository, number)

      # if the issue wasn't found, try searching up the parent chain but only when
      # no explicit repository reference was given (i.e., "foo/bar#33" won't
      # search in other repositories).
      if issuish.nil? && repo.blank?
        while repository = repository.parent do
          issuish = get_referenced_issue(repository, number)
          break if issuish
        end
      end

      # create the IssueReference and add to our list of all issue mentions
      if issuish
        reference = IssueReference.new(issuish, word.to_s)
        issue_mentions << reference
        reference
      end
    end

    # Create a DiscussionReference for the given discussion number and save it in the
    # result hash's :discussion_mentions value.
    #
    # number - The discussion number as an integer.
    # repo   - The Repository object where the discussion should be searched for. May
    #          also be a string '<user>/<repo>' value.
    #
    # Returns a DiscussionReference when the mention is valid, or nil when the
    # discussion could not be found.
    ORG_LEVEL_REFERENCE = /orgs\/([.\w-]+)/
    def discussion_reference(number, repo = nil)
      repository = nil
      if org_match = repo&.match(ORG_LEVEL_REFERENCE)
        org = Organization.find_by(login: org_match[1])
        repository = org&.discussion_repository&.repository
      else
        repository = find_repository(repo)
      end
      return unless can_access_repo?(repository)

      discussion = T.let(nil, T.nilable(Discussion))

      # first try to find the discussion in the current or explicitly
      # referenced repository
      discussion = get_referenced_discussion(repository, number)

      # if the discussion wasn't found, try searching up the parent chain but only when
      # no explicit repository reference was given (i.e., "foo/bar#33" won't
      # search in other repositories).
      if discussion.nil? && repo.blank?
        while repository = repository.parent do
          discussion = get_referenced_discussion(repository, number)
          break if discussion
        end
      end

      # create the DiscussionReference and add to our list of all discussion mentions
      if discussion
        reference = DiscussionReference.new(discussion)
        discussion_mentions << reference
        reference
      end
    end

    # Internal: get the referenced issue, checking
    # to see if an issue should even be referenced
    # (no issue, issues disabled, &c)
    #
    # repository - issue repository
    # number     - issue/PR number
    #
    # Returns an Issue if this is a valid reference.
    # Returns nil if not.
    sig { params(repository: Repository, number: T.untyped).returns(T.nilable(Issue)) }
    def get_referenced_issue(repository, number)
      if (issue = repository.issues.find_by(number: number))
        # PRs can't be disabled, so return the Issue
        # for a PR even if Issues are disabled
        if repository.has_issues || issue.pull_request?
          issue
        end
      end
    end

    # Internal: get the referenced discussion, checking
    # to see if an discussion should even be referenced
    # (no discussion, discussions disabled, &c)
    #
    # repository - discussion repository
    # number     - discussion number
    #
    # Returns a Discussion if this is a valid reference.
    # Returns nil if not.
    sig { params(repository: Repository, number: T.untyped).returns(T.nilable(Discussion)) }
    def get_referenced_discussion(repository, number)
      if repository.discussions_active?
        repository.discussions.find_by(number: number)
      end
    end

    # Finds the IssueReference for a given commit message,
    # if one exists.
    #
    # Used on commit messages like "Bugfix. Closes #3".
    #
    # message - String commit message to search for references.
    # issue - Optional Issue object to match against.
    #
    # Returns an instance of GitHub::HTML::IssueReference if one is found.
    # Returns nil if the message doesn't close an Issue.
    REPO_CLOSE_ISSUE_REFERENCE = /#{CLOSE_LEADER}#{NAME_OR_NWO}?#{MARKER}#{NUMBER}/i
    MAX_COMMIT_MESSAGE_LENGTH = 65536
    def self.extract_close_reference(message, issue = nil)
      return unless message
      message = message[0, MAX_COMMIT_MESSAGE_LENGTH]

      message.scan(REPO_CLOSE_ISSUE_REFERENCE) do
        word, nwo, number = $1, $2, $3.to_i
        if issue
          next unless issue.number == number
        end

        return GitHub::HTML::IssueReference.new(nil, word.to_s)
      end

      nil
    end

    CLOSE_TEXT = /\b(close[sd]?|fix(e[sd])?|resolve[sd]?)\s*:?\s*\z/i
    # Public: Check the given text for a closing keyword
    #
    # Returns String closing keyword if found
    # Returns nil if no keyword found
    def self.close_text(text)
      return unless text
      return unless md = text.match(CLOSE_TEXT)
      md[1]
    end

    # Public: Return the relevant discussion comment or nil.
    #
    # Discussion - a discussion record
    # anchor - String from a link; the anchor on the page may or may not contain a DiscussionComment ID
    #
    # If the anchor refers to a discussion comment but the id doesn't return a
    # record, this returns nil.
    def self.references_threaded_discussion_comment?(discussion, anchor)
      current_user = if actor_id = GitHub.context[:actor_id]
        User.find_by(id: actor_id)
      end
      if anchor&.match(DISCUSSION_COMMENT_REGEX)
        comment_id = anchor.match(DISCUSSION_COMMENT_REGEX).captures.first
        discussion_comment = discussion.comments.filter_spam_for(current_user).find_by_id(comment_id)
        discussion_comment&.threaded?
      end
    end

    private

    # Private: Build hovercard data attributes from an anchor
    #
    # discussion - the Discussion
    # anchor - the part of the URL after the hash, if any
    #
    # Returns a hash to be passed as `data` to a rails helper
    def discussion_hovercard_data_attributes(discussion, anchor:)
      return {} if context[:disable_hovercard_attributes]

      repo = discussion.repository
      return {} unless repo && repo.owner

      comment_id, comment_type = self.class.comment_id_and_type_from(anchor)
      HovercardHelper.hovercard_data_attributes_for_discussion(
        repo.owner.display_login,
        repo.name,
        discussion.number,
        comment_id: comment_id,
      )
    end

    # Private: Build hovercard data attributes from an anchor
    #
    # issue - the Issue
    # anchor - the part of the URL after the hash, if any
    #
    # Returns a hash to be passed as `data` to a rails helper
    def issue_hovercard_data_attributes(issue, anchor:)
      return {} if context[:disable_hovercard_attributes]

      comment_id, comment_type = self.class.comment_id_and_type_from(anchor)
      HovercardHelper.hovercard_data_attributes_for_issue_or_pr(
        issue,
        comment_id: comment_id,
        comment_type: comment_type,
      )
    end
  end
end
