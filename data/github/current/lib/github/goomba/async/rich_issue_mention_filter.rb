# typed: true
# rubocop:disable Primer/PrimerOcticon
# frozen_string_literal: true

module GitHub::Goomba::Async
  # Processes issue references generated in GitHub::Goomba::IssueMentionFilter,
  # replacing the tags with the appropriate result when necessary.
  #
  # Read the documentation of GitHub::Goomba::IssueMentionFilter first to note
  # how plain text and link target references are generated.
  #
  # This builds on the issue scanning functionality in GitHub::Goomba::Async::IssueMentionFilter
  # to find all issue and discussion references in the document.
  #
  # Plain text references
  # =====================
  #
  # Given the following tag:
  #
  #   <gh:issue-mention nwo="github/github"
  #                     marker="#"
  #                     number="99872"></gh:issue-mention>
  #
  # Note that the nwo attribute of a <gh:issue-mention> tag always contains the
  # nwo exactly as written. We can infer that "github/github#99872" was the text
  # entered by the user. #call_gh will look up the nwo/number pair, and if
  # found, insert a link to the issue with a normalized nwo, the given marker,
  # and number; if not found, it'll restore the text as it was.
  #
  # "Normalized nwo" here means that a reference to an issue in the same
  # repository will omit the nwo entirely in the output text; i.e.
  # "github/github#99872" in the github/github repository will be linked with
  # the text "#99872". Similarly, a reference to an issue in a different
  # repository in the same network will include the owner name before the
  # marker.  If the repositories are unrelated, the full nwo will be used.
  #
  #
  # Link target references
  # ======================
  #
  # These are regular <a> tags with the gh:issue-mention attribute. There are
  # two cases with link target references:
  #
  # 1. The HTML content of the link exactly matches the link target, such as <a
  #    href="https://github.com/github/github/issues/99872"
  #    gh:issue-mention="{…}">https://github.com/github/github/issues/99872</a>.
  #    This will occur any time a link to an Issue, PR or comment is pasted into
  #    a Markdown document bare, as our Markdown processor will autolink the
  #    URL. A user could also manually write such a link.
  #
  # 2. The HTML content of the link does not match the link target, such as <a
  #    href="https://github.com/github/github/issues/99872"
  #    gh:issue-mention="{…}">See here</a>. This will happen any other time a
  #    link to an issue is created.
  #
  # It's worth noting that there's nothing special about the parsed data in the
  # gh:issue-mention attribute — we parsed the data out of the URL at the time
  # we added the attribute, so we save ourselves work by not reparsing the URL
  # in this filter, as we need access to the data in both #async_scan and #call.
  #
  #
  # HTML content matches link target
  # --------------------------------
  #
  # In this common case, we note that the href tag matches the inner HTML of the
  # anchor. As long as the referenced issue actually exists, we replace the
  # anchor with a fully-blown "issue link", which contains additional metadata
  # tags for our JavaScript to show the issue title in a popup. The text of
  # created link is the normalized nwo (see above), followed by a "#" and the
  # issue number.
  #
  # The URL might include an anchor, such as "#issuecomment-428066274",
  # "#pullrequestreview-162721744", or "#commits-pushed-7110086". The kind of
  # anchor will be used to determine additional text clarifying what is being
  # linked to, rendering link texts such as "#99872 (comments)", "#99872
  # (review)" or "#99872 (commits)".
  #
  #
  # HTML content does not match link target
  # ---------------------------------------
  #
  # In this less common case, we only add hovercard data attributes, and return anchor tag as
  # is. The result is that the user's link works as they intended, and that any content inside the
  # link was processed by the rest of the pipeline as expected, but that we still create issue
  # references for the link.
  #
  class RichIssueMentionFilter < IssueMentionFilter
    include OcticonsHelper
    include EscapeHelper
    include GitHub::Memoizer

    def self.feature_flags
      [:tasklist_block_precache]
    end

    def self.cache_key(context)
      return "unfurl_references" if context[:unfurl_references]
      nil
    end

    def initialize(*args)
      super

      @filter = GitHub::HTML::IssueMentionFilter.new("", context, result)
      @rich_unfurl_enabled = context[:unfurl_references]
      @project_from_context = context[:memex_project]
      @tasklist_block_precache_enabled = context[:entity].is_a?(Repository) &&
        GitHub.flipper[:tasklist_block_precache].enabled?(context[:entity].owner)
    end

    # When processing a ```[tasklist] block:
    # - Don't process tasklist items with only a single issue mention.
    #   These will be processed in the TasklistBlockFilter and shown as an issue instead of a draft issue.
    #   Ex: "[ ] #1234"
    # - Do process issue mentions that are part of a draft issue.
    #   Ex: "[ ] Some text before an issue #1234"
    def should_process_node?(node)
      return true if @tasklist_block_precache_enabled
      return true unless context[:original_tasklist_items] && context[:original_tasklist_items]&.length > 0
      return true unless node.parent.children.length == 2

      first_child = node.parent.children[0]
      second_child = node.parent.children[1]

      # Match to end of line to avoid matching leading plaintext in the tasklist item.
      has_checkbox_only = first_child.text_content.match?(/#{TaskList::Filter::ItemPattern}\s*\z/)
      has_issue_mention = second_child.matches(GitHub::Goomba::Async::IssueMentionFilter::SELECTOR)
      !(has_checkbox_only && has_issue_mention)
    end

    def is_tracking_block_item_reference?(node)
      return false unless @tasklist_block_precache_enabled
      tracking_block_list_item = find_node_ancestor(node, "li.TrackingBlock-item")
      return false unless tracking_block_list_item

      !tracking_block_list_item["data-draft-issue"]
    end

    # Translates a `<gh:issue-mention>` tag into regular HTML.
    def call_gh(node)
      return nil if !should_process_node?(node)

      nwo, marker, number =
        node["nwo"], node["marker"], node["number"]

      reference = issue_reference(nwo, number) || discussion_reference(nwo, number)

      original_text = "#{nwo}#{marker}#{number}"
      return original_text unless reference

      link = if is_tracking_block_item_reference?(node)
        tasklist_block_item_link(reference)
      else
        gh_reference_link(reference, node)
      end

      repository_resource_reference_wrapper(reference.belonging) do |wrapper|
        wrapper.authorized { link }
        wrapper.unauthorized { original_text }
      end
    end

    # Translates a `<a gh:issue-mention="...">` tag into regular HTML.
    def call_a(node)
      return nil if !should_process_node?(node)

      data = JSON.parse(node["gh:issue-mention"] || node["gh:discussion-mention"])
      nwo, number, anchor =
        data["nwo"], data["number"], data["anchor"]

      node.remove_attribute("gh:issue-mention")
      node.remove_attribute("gh:discussion-mention")

      reference = issue_reference(nwo, number) || discussion_reference(nwo, number)
      return nil unless reference

      # the original node html (without the gh:*-mention attribute) is used for the unauthorized text case
      original_node_html = node.to_html

      link = if is_tracking_block_item_reference?(node)
        tasklist_block_item_link(reference)
      else
        a_reference_link(reference, node, data)
      end

      repository_resource_reference_wrapper(reference.belonging) do |wrapper|
        wrapper.authorized { link }
        wrapper.unauthorized { original_node_html }
      end
    end

    def tasklist_block_item_link(reference)
      issue = reference.issue
      component = Issues::IssueHrefComponent.new(
        owner: issue.repository.owner.display_login,
        repository: issue.repository.name,
        issue_number: issue.number,
        issue_title: issue.title,
        issue_url: issue.url,
        issue_state: issue.state,
        issue_state_reason: issue.state_reason,
        render_context: {
          current_owner: context[:subject]&.repository&.owner&.display_login,
          current_repository: context[:subject]&.repository&.name,
          style_link_normal: true,
          hovercard_attributes: safe_data_attributes(HovercardHelper.hovercard_data_attributes_for_issue_or_pr(issue))
        }
      )
      ApplicationController.render(component, formats: [:html], layout: false)
    end

    def gh_reference_link(reference, node)
      nwo, marker, number =
        node["nwo"], node["marker"], node["number"]

      components = link_components(reference, node)
      unfurled = components.present?

      if components.nil?
        nwo = normalize_nwo(nwo, reference.belonging) unless reference.belonging.nil?
        components = {
          text: "#{nwo}#{marker}#{number.to_i}",
          icon: ""
        }
      end

      text = issue_or_discussion_text(components[:text], components[:shorthand], "")
      if reference.is_a?(GitHub::HTML::IssueReference)
        issue_link(
          reference.belonging.url,
          text,
          before: components[:icon],
          issue: reference.belonging,
          unfurled: unfurled
        )
      elsif reference.is_a?(GitHub::HTML::DiscussionReference)
        discussion_link(
          reference.belonging.url,
          text,
          before: components[:icon],
          discussion: reference.belonging,
          unfurled: unfurled
        )
      else
        components[:text]
      end
    end

    def a_reference_link(reference, node, data)
      href, inner_html = node["href"], node.inner_html
      nwo, number, anchor =
        data["nwo"], data["number"], data["anchor"]

      if href == inner_html
        components = link_components(reference, node)
        unfurled = components.present?

        if components.nil?
          nwo = normalize_nwo(nwo, reference.belonging) unless reference.belonging.nil?
          components = {
            text: "#{nwo}##{number.to_i}",
            icon: ""
          }
        end

        threaded = if reference.is_a?(GitHub::HTML::DiscussionReference)
          GitHub::HTML::IssueMentionFilter.references_threaded_discussion_comment?(reference.discussion, anchor)
        end

        anchor_link_text = anchor_text(anchor, threaded: threaded)
        text = issue_or_discussion_text(components[:text], components[:shorthand], anchor_link_text)
        if reference.is_a?(GitHub::HTML::IssueReference)
          issue_link(
            reference.belonging.url + anchor.to_s,
            text,
            before: components[:icon],
            issue: reference.belonging,
            anchor: anchor,
            unfurled: unfurled
          )
        elsif reference.is_a?(GitHub::HTML::DiscussionReference)
          discussion_link(
            reference.belonging.url + anchor.to_s,
            text,
            before: components[:icon],
            discussion: reference.belonging,
            anchor: anchor,
            unfurled: unfurled
          )
        end
      else
        # Don't change the original node except for adding hovercard data attributes
        if reference.is_a?(GitHub::HTML::IssueReference)
          add_issue_hovercard_attrs_to_node(node, issue: reference.belonging)
        elsif reference.is_a?(GitHub::HTML::DiscussionReference)
          add_discussion_hovercard_attrs_to_node(node, discussion: reference.belonging,
            anchor: anchor)
        end

        node
      end
    end

    # Rich issue and discussion references always defer authorization checks post-cache
    # to GitHub::Goomba::Reference::RepositoryResourceFilter
    def deferred_authorization_checks_enabled?
      true
    end

    def calculate_readable_references?
      # don't calculate readable references, authorization checks are run post-cache
      false
    end

    # Override the base method to default to true, auth checks will be run post-cache
    def async_bot_can_access_issue_or_discussion?(repo, issue_or_discussion)
      Promise.resolve(true)
    end

    # Override the base method to default to true, auth checks will be run post-cache
    def async_can_access_repo?(repo)
      Promise.resolve(true)
    end

    private

    def is_in_list_item(node)
      ancestor = node.parent
      until ancestor.nil? || ancestor.attributes["class"]&.include?("js-comment-body")

        if ancestor.tag == :li
          return true
        end

        ancestor = ancestor.parent
      end

      false
    end

    def link_components(reference, node)
      return nil unless @rich_unfurl_enabled
      return nil unless is_in_list_item(node)

      if reference.is_a? GitHub::HTML::IssueReference
        return nil if reference.issue.pull_request_id && !reference.issue.pull_request

        {
          text: GitHub::Goomba::TitleMarkdownFilter.call(reference.issue.title),
          icon: get_issue_or_pr_icon(reference.issue),
          shorthand: get_object_shorthand(reference.issue)
        }
      else
        {
          text: reference.discussion.title,
          icon: get_discussion_icon(reference.discussion),
          shorthand: get_object_shorthand(reference.discussion)
        }
      end
    end

    def issue_or_discussion_text(title, shorthand, anchor)
      if shorthand.nil?
        EscapeHelper.safe_join([title, anchor])
      else
        suffix = EscapeHelper.safe_join([GitHub::HTMLSafeString::NBSP, "#{shorthand}#{anchor}"])
        span = ActionController::Base.helpers.content_tag(:span, suffix, { class: "issue-shorthand" })
        EscapeHelper.safe_join([title, span])
      end
    end

    def issue_link(url, text, before: "", issue:, anchor: nil, unfurled: false)
      reference = @filter.issue_link(url, text, before: before, issue: issue, anchor: anchor)
      return reference unless unfurled

      ActionController::Base.helpers.content_tag(:span, reference, { class: "reference" })
    end

    def discussion_link(url, text, before: "", discussion:, anchor: nil, unfurled: false)
      reference = @filter.discussion_link(url, text, before: before, discussion: discussion, anchor: anchor)
      return reference unless unfurled

      ActionController::Base.helpers.content_tag(:span, reference, { class: "reference" })
    end

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
      when /#{GitHub::HTML::IssueMentionFilter::DISCUSSION_COMMENT_DOM_ID_PREFIX}/
        threaded ? "reply in thread" : "comment"
      else
        "comment"
      end

      " (#{text})"
    end

    def get_object_shorthand(object)
      if object.repository == repository
        "##{object.number}"
      elsif object.repository.owner == repository&.owner || object.repository.owner == @project_from_context&.owner
        "#{object.repository.name}##{object.number}"
      else
        "#{object.repository.name_with_display_owner}##{object.number}"
      end
    end

    def get_issue_or_pr_icon(object)
      if object.pull_request_id.nil?
        if object.open?
          octicon("issue-opened", class: "open mr-1", title: "Open")
        else
          if object.state_reason_not_planned?
            not_planned_icon_info = Issue::StateReasonDependency::OCTICONS[:not_planned]
            octicon(not_planned_icon_info[:icon], class: "#{not_planned_icon_info[:class]} mr-1", title: not_planned_icon_info[:title])
          else
            octicon("issue-closed", class: "closed mr-1", title: "Closed")
          end
        end
      else
        icon = PullRequest::Icon.new(
          object.pull_request,
          permit_queued_icon: false, # TODO: Remove this after resolving N+1 issues
        )
        octicon(icon.octicon_name, class: "#{icon.state} color-fg-#{icon.primer_color} mr-1", title: icon.short_label)
      end
    end

    def get_discussion_icon(discussion)
      if discussion.closed?
        reason = discussion_state_reasons_by_value[discussion.state_reason]
        octicon(reason.octicon, class: "color-fg-#{reason.octicon_color} mr-1")
      else
        octicon("comment-discussion", class: "color-fg-muted mr-1")
      end
    end

    # Internal: Adds hovercard attributes to a Goomba::ElementNode.
    #   The original intent of this method was to modify an existing anchor node in the case where
    #   the content doesn't match the href link.
    #
    # node - Goomba::ElementNode
    # hovercard_attrs - a hash of String => String
    #
    # Returns a Goomba::ElementNode
    def add_hovercard_attrs_to_node(node, hovercard_attrs:)
      hovercard_attrs.each_pair do |attribute, val|
        node["data-#{attribute}"] = val
      end

      node
    end

    # Internal: Adds hovercard attributes for an issue to a Goomba::ElementNode.
    # Returns a Goomba::ElementNode
    def add_issue_hovercard_attrs_to_node(node, issue:)
      hovercard_attrs = HovercardHelper.hovercard_data_attributes_for_issue_or_pr(issue)
      add_hovercard_attrs_to_node(node, hovercard_attrs: hovercard_attrs)
    end

    # Internal: Adds hovercard attributes for a discussion to a Goomba::ElementNode.
    # Returns a Goomba::ElementNode
    def add_discussion_hovercard_attrs_to_node(node, discussion:, anchor: nil)
      repo = discussion.repository
      return node unless repo

      comment_id, _ = GitHub::HTML::IssueMentionFilter.comment_id_and_type_from(anchor)
      hovercard_attrs = HovercardHelper.hovercard_data_attributes_for_discussion(
        repo.owner&.display_login,
        repo.name,
        discussion.number,
        comment_id: comment_id,
      )
      add_hovercard_attrs_to_node(node, hovercard_attrs: hovercard_attrs)
    end

    # Internal: Rewrites the nwo according to the repository context. Uses the current nwo of the
    # repo of the matched issue/discussion.
    #
    # nwo - repository owner/name string
    # record_belonging_to_repo - an Issue or Discussion, something that has a #repository
    #
    # Returns the nwo String for the issue/discussion
    def normalize_nwo(nwo, record_belonging_to_repo)
      record_repo = record_belonging_to_repo.repository

      # If we have a repository context, normalize the reference nwo down to the
      # minimum number of components; none if completely equal, owner only if
      # same network.
      #
      # (We may not have a repository context, e.g. a card in an
      # organisation-level Project.)
      if repository
        return "" if record_repo == repository

        if record_repo.source_id == repository.source_id
          return record_repo.owner.display_login
        end
      end

      # Write out an nwo with the same components as supplied, but fetching the
      # data from the referenced issue/discussion, to account for user and/or
      # repo renames.
      return "" if nwo.blank?
      return record_repo.owner.display_login if !nwo.include?("/")
      record_repo.name_with_display_owner
    end

    memoize def discussion_state_reasons_by_value
      Closables::BaseComponent::DISCUSSION_REASONS.index_by(&:value)
    end
  end
end
