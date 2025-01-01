# typed: false
# rubocop:disable Primer/PrimerOcticon
# frozen_string_literal: true

module NewsFeedHelper
  include FeatureFlagHelper
  include GitHub::Memoizer

  DOGSTATS_TIMEOUT_THRESHOLD_SECONDS = 2
  FAILBOT_TIMEOUT_THRESHOLD_SECONDS = 2

  class GroupedPushEventsError < StandardError; end
  class GroupedPushEventsDogstatsTimeout < StandardError; end
  class GroupedPushEventsFailbotTimeout < StandardError; end

  def include_event_star_button?
    logged_in? && !atom_feed?
  end

  def include_event_follow_button?(followed_user_ids)
    !followed_user_ids.nil? && logged_in? && !atom_feed?
  end

  # Public: Given an Events::View instance and an analytics key, this will return a hash
  # for use in `data-` attributes on an HTML element, such as a link, for telling Hydro
  # and Google Analytics about interactions with that element.
  #
  # event_view - an Events::View
  # key - String; describes the HTML element, such as what the link is targeting
  #
  # Returns a Hash.
  def event_analytics_attributes(event_view, key)
    return {} if atom_feed?
    event_view.analytics_attributes_for(key, org_id: current_organization&.id,
                                        viewer: current_user)
  end

  # Public: Render a group of dashboard news feed events, including logging analytics of the view.
  #
  # group_view - a `Dashboard::EventGroupView` instance
  # locals - a Hash of key-value pairs to pass to the partial being rendered
  #
  # Returns HTML.
  def render_event_group(group_view, locals: {})
    partial_locals = locals.merge(group: group_view, has_hovercard: group_view.sender_record.is_a?(User))
    render partial: "dashboard/grouped_events", locals: partial_locals # rubocop:disable GitHub/RailsViewRenderLiteral
  end

  def render_grouped_push_event_commits(commit_group, is_visible:)
    render partial: "dashboard/grouped_commits", locals: { commit_group: commit_group, is_visible: is_visible }
  rescue => e # rubocop:todo Lint/RescueException
    raise if Rails.env.test? || Rails.env.development?

    begin
      Timeout.timeout(FAILBOT_TIMEOUT_THRESHOLD_SECONDS, GroupedPushEventsFailbotTimeout) do
        Failbot.report(
          GroupedPushEventsError.new,
          raised_exception_class: e.class,
          backtrace: e.backtrace.take(10),
        )
      end

      Timeout.timeout(DOGSTATS_TIMEOUT_THRESHOLD_SECONDS, GroupedPushEventsDogstatsTimeout) do
        GitHub.dogstats.increment("events.render.failure")
      end
    rescue GroupedPushEventsFailbotTimeout, GroupedPushEventsDogstatsTimeout
      nil
    end

    nil
  end

  def render_grouped_follow_events(events_in_group, is_visible:, locals: {})
    partial_locals = locals.merge(include_title: false)
    render_grouped_events(events_in_group, is_visible: is_visible, locals: partial_locals)
  end

  def render_grouped_issue_comment_events(events_in_group, is_visible:)
    render_grouped_events(events_in_group, is_visible: is_visible,
                          locals: { include_avatar: false, include_title: false,
                                    include_separator: false })
  end

  def render_grouped_pull_request_review_comment_events(events_in_group, is_visible:)
    render_grouped_events(events_in_group, is_visible: is_visible,
                          locals: { include_avatar: false, include_separator: false,
                                    include_title: false })
  end

  def render_grouped_watch_events(events_in_group, is_visible:, locals: {})
    partial_locals = locals.merge(include_avatar: false, include_title: false, include_separator: false)
    render_grouped_events(events_in_group, is_visible: is_visible, locals: partial_locals)
  end

  def render_grouped_fork_events(events_in_group, is_visible:, locals: {})
    partial_locals = locals.merge(include_title: false, include_forked_repo: true)
    render_grouped_events(events_in_group, is_visible: is_visible, locals: partial_locals)
  end

  def render_grouped_public_events(events_in_group, is_visible:, locals: {})
    partial_locals = locals.merge(include_actor: false, include_avatar: false, include_separator: false)
    render_grouped_events(events_in_group, is_visible: is_visible, locals: partial_locals)
  end

  def render_grouped_create_events(events_in_group, is_visible:, locals: {})
    partial_locals = locals.merge({
      always_include_title: false,
      include_separator: false,
      include_avatar: false,
      include_repo_in_title: false,
      include_pusher_in_title: false,
      include_space_above_title: true,
    })
    render_grouped_events(events_in_group, is_visible: is_visible, locals: partial_locals)
  end

  def render_grouped_release_events(events_in_group, is_visible:, locals: {})
    partial_locals = locals.merge(include_title: false)
    render_grouped_events(events_in_group, is_visible: is_visible, locals: partial_locals)
  end

  # Public: Render a group of news feed events.
  #
  # events_in_group - an Array of Stratocaster::Event records
  # is_visible - Boolean indicating if these events are shown when the page loads; pass false
  #              when the events are hidden by default such that a user has to interact with the
  #              page to make them visible
  # locals - local variables to pass to the view when rendering each event
  #
  # Returns rendered HTML for all the given events.
  def render_grouped_events(events_in_group, is_visible:, locals: {})
    views = events_in_group.map do |event|
      event_view = Events::View.for(event, grouped: true)
      render_event(event_view, is_visible: is_visible, locals: locals)
    end
    safe_join(views, "\n")
  end

  def render_event(event_view, is_visible: true, locals: {})
    return unless event_view.should_render?

    start = Time.now
    partial_path = event_view.partial_path
    inner_html = render(partial: partial_path, # rubocop:disable GitHub/RailsViewRenderLiteral
                        locals: locals.merge(event: event_view),
                        formats: [:html], # This may be called from other formats (like an atom feed)
                       )
    elapsed_ms = (Time.now - start) * 1_000
    GitHub.dogstats.distribution("dashboard-news-feed.render.#{partial_path}", elapsed_ms)

    body = content_tag(:div, inner_html, class: "body")

    classes = [event_view.icon, "js-feed-item-view"]
    content_tag(:div, body, {
      class: classes,
      data: event_view.view_attributes(
        org_id: current_organization&.id,
        viewer: current_user
      )
    })
  rescue => exception # rubocop:todo Lint/RescueException
    raise if Rails.env.test? || Rails.env.development?
    GitHub.dogstats.increment("events.render.failure")
    Failbot.report(exception, event: event_view, payload: event_view.payload)
    nil
  end

  def link_to_event_wiki_page(gollum_page, event_view)
    link_to(
      gollum_page.wiki_title,
      gollum_page.url,
      data: event_analytics_attributes(event_view, "wiki-page"),
    )
  end

  def link_to_event_group_actor(group_view, event_view: nil, classes: nil)
    attributes = NewsFeedAnalytics.event_click_attributes(
      event_view || group_view.first_event,
      event_details: { grouped: true },
      target: "actor",
      org_id: current_organization.try(:id),
      viewer_id: current_user.try(:id),
    )

    link_to_event_actor(event_view || group_view, analytics_data: attributes, classes: classes)
  end

  def link_to_event_actor(event_view, analytics_data: nil, classes: nil, hovercard: true)
    if event_view.sender_record
      include_hovercard = hovercard && event_view.sender_record.user?
      link_to(
        event_view.sender_record&.display_login,
        user_path(event_view.sender_record),
        data: event_actor_data_attributes(event_view, hovercard: include_hovercard,
                                          analytics_data: analytics_data),
        class: classes || "Link--primary no-underline text-bold wb-break-all d-inline-block",
      )
    else
      "(deleted)"
    end
  end

  def link_to_event_actor_name(event_view)
    if event_view.sender_record
      link_to(
        event_view.sender_name,
        user_path(event_view.sender_record),
        data: event_actor_data_attributes(event_view, hovercard: false),
        class: "f4 text-bold Link--primary no-underline",
      )
    end
  end

  # Public: Returns a hash of analytics data for use in `data-` attributes on a link to
  # the actor of an event.
  def event_actor_data_attributes(event_view, analytics_data: nil, hovercard: true)
    data = if hovercard
      hovercard_data_attributes_for_user_login(event_view.actor_login)
    else
      {}
    end
    if analytics_data
      data.merge(analytics_data)
    else
      data.merge(event_analytics_attributes(event_view, "actor"))
    end
  end

  def link_to_event_forked_repo(event_view, classes: nil)
    if event_view.forked_repo_name
      classes ||= "Link--primary no-underline text-bold wb-break-all d-inline-block"
      link_to(event_view.forked_repo_name, "/#{event_view.forked_repo_name}",
        class: classes,
        title: event_view.forked_repo_name,
        data: event_analytics_attributes(event_view, "parent")
      )
    else
      "deleted"
    end
  end

  def link_to_event_avatar(event_view, test_selector_name: nil)
    link_options = {
      class: "d-inline-block",
      data: event_analytics_attributes(event_view, "actor"),
    }.merge(test_selector_data_hash(test_selector_name))
    content_tag(:span, class: "mr-2") do
      profile_link(event_view.sender_record, link_options) do
        avatar_for(event_view.sender_record, 32, class: "avatar")
      end
    end
  end

  def link_to_event_repo(event_view, hovercard: true, include_owner: true, classes: nil)
    if nwo = event_view.repo_nwo
      data_attrs = event_analytics_attributes(event_view, "repo")
      classes ||= "Link--primary text-bold no-underline wb-break-all d-inline-block"
      if hovercard && !atom_feed?
        owner, name = nwo.split("/")
        data_attrs.merge!(hovercard_data_attributes_for_repo_owner_and_name(owner, name))
      end
      link_to(
        include_owner ? nwo : name,
        "/#{nwo}",
        data: data_attrs,
        class: classes,
      )
    else
      "(deleted)"
    end
  end

  def event_repo_reaction_path(event_view)
    if nwo = event_view.repo_nwo
      "/#{nwo}/reactions"
    end
  end

  def link_to_event_repo_owner_avatar(event_view, size: 16, classes: nil, test_selector_name: "repo-owner-avatar")
    if repo_owner = event_view.repo_owner
      data_attrs = event_analytics_attributes(event_view, "repo-owner").merge(test_selector_hash(test_selector_name))
      classes ||= "d-flex"
      profile_link(
        repo_owner,
        class: classes,
        data: data_attrs
      ) do
        render GitHub::AvatarComponent.new(actor: repo_owner, size: size)
      end
    end
  end

  def link_to_event_repo_owner(event_view, classes: nil)
    if repo_owner = event_view.repo_owner
      data_attrs = event_analytics_attributes(event_view, "repo_owner")
      if repo_owner.is_a?(Organization)
        data_attrs.merge!(hovercard_data_attributes_for_org(login: repo_owner.login))
      else
        data_attrs.merge!(hovercard_data_attributes_for_user_login(repo_owner.login))
      end

      link_to(
        repo_owner,
        "/#{repo_owner}",
        data: data_attrs,
        class: classes || "Link--primary no-underline text-bold wb-break-all d-inline-block",
      )
    else
      "(deleted)"
    end
  end

  def link_to_push_event_branch(event_view)
    if nwo = event_view.repo_nwo
      path = "/%s/tree/%s" % [nwo, event_view.ref_name]
      link_to(
        h(event_view.ref_name),
        escape_url_branch(path),
        class: "branch-name",
        data: event_analytics_attributes(event_view, "branch"),
      )
    else
      "(deleted)"
    end
  end

  def link_to_event_head(event_view)
    if nwo = event_view.repo_nwo
      path = "/%s/tree/%s" % [nwo, event_view.head]
      link_to(
        event_view.head[0, 7],
        path,
        data: event_analytics_attributes(event_view, "head"),
      )
    else
      "(deleted)"
    end
  end

  def link_to_event_sha(commit_view)
    push_view = commit_view.push
    if nwo = push_view.repo_nwo
      path = "/%s/commit/%s" % [nwo, commit_view.sha]
      link_to(
        commit_view.sha.first(7),
        path,
        class: "mr-1",
        data: { **event_analytics_attributes(push_view, "sha").symbolize_keys, **hovercard_data_attributes_for_commit(commit_url: path).symbolize_keys },
      )
    else
      "(deleted)"
    end
  end

  def link_to_more_event_pages(event_view)
    count = number_with_delimiter(event_view.remaining_page_count)
    link_to(event_view.wiki_path, data: event_analytics_attributes(event_view, "wiki")) do
      safe_join([
        pluralize(count, "more edit"),
        "»",
      ], " ")
    end
  end

  def link_to_event_wiki_compare(gollum_page, event_view)
    link_to(
      gollum_page.summary || "View the diff »",
      gollum_page.compare_url,
      class: "f6 Link--primary text-bold",
      data: event_analytics_attributes(event_view, "wiki-compare"),
    )
  end

  def link_to_event_comparison(event_view)
    return unless event_view.repo_nwo

    text = if event_view.more_commits?
      count = event_view.remaining_commit_count
      "#{number_with_delimiter(count)} more #{"commit".pluralize(count)} »"
    end

    return unless text

    link_to(
      text,
      event_view.url,
      class: "Link--secondary",
      data: event_analytics_attributes(event_view, "comparison"),
    )
  end

  def link_to_event_repo_stargazers(event_view)
    link_to(
      event_repo_stargazers_with_icon(event_view),
      event_view.repo_stargazers_path,
      data: event_analytics_attributes(event_view, "stargazers"),
      class: "Link--muted",
    )
  end

  def link_to_event_issue(event_view)
    if event_view.number
      link_to(event_view.subject, event_view.url,
        :title => event_view.subject,
        :class => "color-fg-default",
        "aria-label" => event_view.subject,
        :data => event_analytics_attributes(event_view, "issue")
      )
    else
      "(deleted)"
    end
  end

  def link_to_event_pull(event_view, link_text: nil, classes: nil)
    if event_view.issue_number && event_view.issue_number > 0
      link_text ||= event_view.pull_title
      classes ||= "color-fg-default text-bold"
      link_to(
        link_text, event_view.url,
        :class => classes,
        "aria-label" => link_text,
        :data => event_analytics_attributes(event_view, "pull")
      )
    else
      "(deleted)"
    end
  end

  def link_to_event_created_object_and_repo(event_view, include_repository: true)
    link_class = if event_view.branch?
      "css-truncate css-truncate-target branch-name v-align-middle"
    else
      "Link--primary text-bold"
    end
    object_link = link_to(event_view.object_name, event_view.tree_path,
      class: link_class,
      title: event_view.object_name,
      data: event_analytics_attributes(event_view, event_view.analytics_target)
    )
    parts = if include_repository && !event_view.repository?
      if event_view.repo_nwo
        [object_link, "in", link_to_event_repo(event_view)]
      else
        [object_link, "in (deleted)"]
      end
    else
      [object_link]
    end
    safe_join(parts, " ")
  end

  def link_to_event_release(
    event_view,
    text: event_view.release_title,
    link_class: "Link--primary no-underline text-bold wb-break-all d-inline-block"
  )
    return unless event_view.release_title && event_view.release_path

    link_to(h(text), event_view.release_path, class: link_class,
            data: event_analytics_attributes(event_view, "release"))
  end

  def link_to_event_release_discussion(event_view, discussion_number:, &block)
    data_attrs = event_analytics_attributes(event_view, "release-discussion").merge(
      test_selector_hash("release-event-discussion")
    )
    link_to(
      "/#{event_view.repo_nwo}/discussions/#{discussion_number}",
      class: "note no-underline",
      data: data_attrs
    ) do
      yield block
    end
  end

  def link_to_event_member(event_view, classes: nil)
    if event_view.member_login
      link_to(
        event_view.member_login,
        "/#{event_view.member_login}",
        class: classes || "text-bold Link--primary",
        data: event_analytics_attributes(event_view, "member"),
      )
    else
      "someone"
    end
  end

  def link_to_event_help_wanted_issues(event_view)
    link_text = event_help_wanted_issues_description(event_view)
    if link_text.present? && event_view.help_wanted_issues_path
      link_to(
        link_text,
        event_view.help_wanted_issues_path,
        data: event_analytics_attributes(event_view, "help wanted"),
        class: "Link--muted",
      )
    end
  end

  def event_help_wanted_issues_description(event)
    if event.repo_help_wanted_issues_count > 0
      issues_count = pluralize(event.repo_help_wanted_issues_count, "issue")
      need = if event.repo_help_wanted_issues_count == 1
        "needs"
      else
        "need"
      end

      "#{issues_count} #{need} help"
    end
  end

  # Public: Return an avatar linked to the user profile.
  #
  # commit_view - an Events::PushView::CommitView instance
  #
  # Returns HTML.
  def avatar_for_event_user(commit_view)
    if commit_view.user
      linked_avatar_for(commit_view.user, 16, img_class: "mr-1")
    else
      gravatar_for_email(commit_view.email, 16, class: "mr-1")
    end
  end

  def link_to_event_actor_repos(event_view)
    link_text = pluralize(event_view.actor_public_repos_count, "repository")
    url = "#{user_path(event_view.actor_login)}?tab=repositories"
    link_to(link_text, url, data: event_analytics_attributes(event_view, "repositories"),
            class: "Link--muted")
  end

  def link_to_event_target_repos(event_view)
    link_text = pluralize(event_view.target_public_repos_count, "repository")
    url = "#{user_path(event_view.target_login)}?tab=repositories"
    link_to(link_text, url, data: event_analytics_attributes(event_view, "repositories"),
            class: "Link--muted")
  end

  def link_to_event_actor_followers(event_view)
    followers_count = social_count(event_view.actor_followers_count)
    unit = "follower".pluralize(event_view.actor_followers_count)
    link_text = "#{followers_count} #{unit}"
    url = "#{user_path(event_view.actor_login)}?tab=followers"
    link_to(link_text, url, data: event_analytics_attributes(event_view, "followers"),
            class: "Link--muted")
  end

  def link_to_event_target_followers(event_view)
    followers_count = social_count(event_view.target_followers_count)
    unit = "follower".pluralize(event_view.target_followers_count)
    link_text = "#{followers_count} #{unit}"
    url = "#{user_path(event_view.target_login)}?tab=followers"
    link_to(link_text, url, data: event_analytics_attributes(event_view, "followers"),
            class: "Link--muted")
  end

  def link_to_event_actor_avatar(event_view)
    if event_view.sender_record
      link_to(user_path(event_view.sender_record), title: event_view.actor_login,
              data: event_analytics_attributes(event_view, "actor")) do
        image_tag(event_view.actor_avatar_url, class: "#{avatar_class_names(event_view.sender_record)} mr-2", size: "40x40",
                  alt: event_view.actor_login)
      end
    end
  end

  def link_to_event_target_avatar(event_view)
    if event_view.target_login
      link_to(user_path(event_view.target_login), title: event_view.target_login,
              data: event_analytics_attributes(event_view, "followee")) do
        image_tag(event_view.target_avatar_url, class: "avatar avatar-user mr-2", size: "40x40",
                  alt: event_view.target_login)
      end
    end
  end

  def link_to_event_target_login(event_view, classes: nil)
    if event_view.target_login
      link_to(
        event_view.target_login,
        "/#{event_view.target_login}",
        data: event_analytics_attributes(event_view, "followee"),
        class: classes,
      )
    else
      "(deleted)"
    end
  end

  def event_repo_stargazers_with_icon(event_view)
    safe_join([
      octicon(:star, class: "mr-1"),
      social_count(event_view.repo_stargazers_count),
    ])
  end

  def event_pusher_bot_identifier(event_view)
    case event_view.pusher_type.to_s
    when "user", ""
      bot_identifier(event_view.sender_record)
    end
  end

  def link_to_event_target_name(event_view, classes: nil)
    link_to(
      event_view.target_name,
      "/#{event_view.target_login}",
      data: event_analytics_attributes(event_view, "followee"),
      class: classes,
    )
  end

  def link_to_event_pusher(event_view, classes: nil)
    case event_view.pusher_type.to_s
    when "user", ""
      link_to_event_actor(event_view, classes: classes)
    else
      event_view.pusher_text
    end
  end

  def link_to_event_issue_comment_issue(event_view, classes: nil, tooltip: false)
    if event_view.number
      classes ||= "Link--primary text-bold"
      options = {
        class: classes,
        data: event_analytics_attributes(event_view, "issue-comment"),
      }
      if tooltip && event_view.issue_title
        options[:class] += " tooltipped tooltipped-n"
        options[:"aria-label"] = event_view.issue_title
      else
        options[:title] = event_view.issue_title
      end
      link_to(event_view.issue_text, event_view.url, options)
    else
      "(deleted)"
    end
  end

  # Public: Returns a link to a comment on a commit where the text of the link includes the
  # commenter's avatar, name, and a timestamp.
  def link_to_event_commit_comment_with_actor(event_view)
    link_to(
      event_actor_commented_text(event_view),
      event_view.comment_html_url,
      class: "Link--secondary",
      data: event_analytics_attributes(event_view, "commit-comment"),
    )
  end

  # Public: Returns a link to a comment on a commit where the text of the link includes the
  # repository name and the sha of the commit.
  def link_to_event_commit_comment(event_view, classes: nil)
    classes ||= "Link--primary text-bold"
    if event_view.commit_sha.present? && event_view.comment_html_url
      link_to(
        event_view.commit_sha_summary,
        event_view.comment_html_url,
        class: classes,
        data: event_analytics_attributes(event_view, "commit-comment"),
      )
    end
  end

  def link_to_event_pr_review_comment(event_view, link_text: nil, classes: nil, tooltip: false)
    if event_view.pull_comment_url
      options = {
        class: classes || "Link--primary text-bold",
        data: event_analytics_attributes(event_view, "pull-comment"),
      }
      if tooltip && event_view.pull_request_title
        options[:class] += " tooltipped tooltipped-n"
        options[:"aria-label"] = event_view.pull_request_title
      else
        options[:title] = event_view.pull_request_title
      end
      link_to(
        link_text || event_view.pull_text,
        event_view.pull_comment_url,
        options,
      )
    else
      "(deleted)"
    end
  end

  def link_to_event_issue_comment(event_view)
    if event_view.number
      link_to(
        event_actor_commented_text(event_view),
        event_view.url,
        title: event_view.issue_title,
        class: "Link--secondary",
        data: event_analytics_attributes(event_view, "issue-comment"),
      )
    end
  end

  def event_actor_commented_text(event_view)
    safe_join([
      avatar_for(event_view.sender_record, 16, class: "avatar mr-1"),
      content_tag(:span, event_view.sender_record, class: "Link--primary text-bold"),
      "commented",
      time_ago_in_words_js(event_view.created_at),
    ], " ")
  end

  def card_container_classes(include_separator: true)
    class_names(
      "d-flex flex-items-baseline",
      "py-4" => include_separator,
    )
  end

  def header_should_use_repo_owner_context?(event_view:, followed_user_ids: [], starred_repo_ids: [])
    return false if followed_user_ids.nil? || starred_repo_ids.nil?
    starred_repo_ids.include?(event_view.repo_id) || !followed_user_ids.include?(event_view.actor_id)
  end

  def mona_loader_picture(attrs = {})
    mona_map = {
      light: "mona-loading-default.gif",
      dark: "mona-loading-dark.gif",
      dark_high_contrast: "mona-loading-dark.gif",
      dark_dimmed: "mona-loading-dimmed.gif"
    }

    color_theme_picture_tag(mona_map, **attrs)
  end

  def mona_loader_static_picture(attrs = {})
    mona_map = {
      light: "mona-loading-default-static.svg",
      dark: "mona-loading-dark-static.svg",
      dark_high_contrast: "mona-loading-dark-static.svg",
      dark_dimmed: "mona-loading-dimmed-static.svg"
    }

    color_theme_picture_tag(mona_map, **attrs)
  end
end
