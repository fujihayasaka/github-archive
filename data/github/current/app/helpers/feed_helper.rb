# typed: false
# frozen_string_literal: true

module FeedHelper
  FEEDBACK_URLS = {
    staff: "https://github.com/github/feeds/discussions/1845",
    private_beta: "https://github.com/gh-community/feed-feedback",
    public_beta: "https://github.com/orgs/github-community/discussions/categories/feed"
  }

  # Public: Get a link to a repository
  #
  # repo - A Repository to link to
  # feed_item - Conduit::FeedItem - with repository
  # data [optional] - A Hash of data attributes to pass to the link
  # include_owner [optional] - A boolean to include the owner in the link
  # system_arguments - A Hash of [system arguments](https://primer.style/view-components/system-arguments) to pass to the link
  def link_to_feed_repo(repo, feed_item, data: {}, include_owner: false, **system_arguments)
    if repo&.owner.present? && repo&.name.present?

      metadata = {
        clicked_resource_type: Conduit::AnalyticsHelper::ResourceType::REPOSITORY,
        clicked_resource_id: repo.id,
      }
      data.merge!(feed_clicks_hydro_attrs(
        click_target: "repository_link",
        feed_item: feed_item,
        metadata: metadata
      ))
      data.merge!(hovercard_data_attributes_for_repository(repo, url_params: {
        event_type: "feeds.feed_click",
        payload: {
          feed_card: feed_item.analytics_attributes,
          original_request_id: feed_item.request_id,
          metadata: metadata
        }
      }))

      render(Primer::Beta::Link.new(
        href: "/#{repo.name_with_display_owner}",
        data: data,
        scheme: :primary,
        underline: false,
        font_weight: :bold,
        test_selector: "link_to_feed_repo",
        **system_arguments
      )) { include_owner ? "#{repo.name_with_display_owner}" : repo.name }
    else
      "(deleted)"
    end
  end

  # Public: Get a link to a user
  #
  # user - A User to link to
  # feed_item - Conduit::FeedItem - with repository
  # show_profile_name [optional] - A boolean to show the user's profile name, if set
  # data [optional] - A Hash of data attributes to pass to the link
  # system_arguments - A Hash of [system arguments](https://primer.style/view-components/system-arguments) to pass to the link
  def link_to_feed_user(user, feed_item, show_profile_name: false, data: {}, **system_arguments)
    return "(deleted)" if user.nil?

    metadata = {
      clicked_resource_type: Conduit::AnalyticsHelper::ResourceType::USER,
      clicked_resource_id: user.id,
    }

    data.merge!(feed_clicks_hydro_attrs(
      click_target: "feed_user_link",
      feed_item: feed_item,
      metadata: metadata
    ))
    data.merge!(hovercard_attrs_for_user(user, url_params: {
      event_type: "feeds.feed_click",
      hover_target: "feed_user_login",
      payload: {
        feed_card: feed_item.analytics_attributes,
        original_request_id: feed_item.request_id,
        metadata: metadata
      }
    }))

    name = user.display_login
    if show_profile_name && user.profile_name.present? && !user.is_a?(Bot)
      name = user.profile_name.strip
    end

    render(Primer::Beta::Link.new(
      href: url_for_user(user),
      data: data,
      scheme: :primary,
      underline: false,
      font_weight: :bold,
      test_selector: "link_to_feed_user",
      **system_arguments
    )) { name }
  end

  # Public: Get the user login
  #
  # user - A user
  # system_arguments - A Hash of [system arguments](https://primer.style/view-components/system-arguments) to pass to the link
  def feed_user_login_name(user, **system_arguments)
    return "" if user.nil?

    if !user.profile_name.present? || user.is_a?(Bot)
      return ""
    end

    render(Primer::Beta::Text.new(
      tag: :span,
      color: :muted,
      font_weight: :normal
      )) { user.display_login }
  end

  # Public: Returns an avatar wrapped in a link for a user
  #
  # user - A User to display the avatar for
  # size - An Integer representing the size of the avatar
  # feed_item - Conduit::FeedItem - with repository
  # data [optional] - A Hash of data attributes to pass to the link
  # link_arguments [optional] - A Hash of [system arguments](https://primer.style/view-components/system-arguments) to pass to the link
  # system_arguments - A Hash of [system arguments](https://primer.style/view-components/system-arguments) to pass to the avatar
  def feed_user_avatar(user, feed_item, size: 32, data: {}, link_arguments: {}, **system_arguments)
    return if user.nil?

    metadata = {
      clicked_resource_type: Conduit::AnalyticsHelper::ResourceType::USER,
      clicked_resource_id: user.id,
    }
    data.merge!(feed_clicks_hydro_attrs(
      click_target: "avatar",
      feed_item: feed_item,
      metadata: metadata
    ))
    data.merge!(hovercard_attrs_for_user(user, url_params: {
      event_type: "feeds.feed_click",
      hover_target: "feed_user_avatar",
      payload: {
        feed_card: feed_item.analytics_attributes,
        original_request_id: feed_item.request_id,
        metadata: metadata,
      }
    }))

    avatar_url = avatar_url_for(user, size * 2)

    render(Primer::Beta::Link.new(
      href: url_for_user(user),
      data: data,
      display: :block,
      **link_arguments
    )) do
      render(Primer::Beta::Avatar.new(
        src: avatar_url,
        size: size,
        alt: "@#{user} profile",
        classes: "feed-item-user-avatar",
        box_shadow: :none,
        shape: avatar_user_actor?(user) ? :circle : :square,
        **system_arguments
      ))
    end
  end

  # Public: Returns a hash of attributes to be passed as `data` attributes or `hydro_data` where available to provide analytics and hovercard behavior
  #
  # repo - A Repository that the discussion is associated with
  # number - The number of the discussion
  # feed_item - Conduit::FeedItem
  def feed_discussion_link_data(repo:, number:, click_target: "discussion_link", feed_item:)
    feed_clicks_hydro_attrs(
      click_target: click_target,
      feed_item: feed_item
    ).merge(hovercard_data_attributes_for_discussion(
      repo.owner_display_login,
      repo.name,
      number,
      url_params: {
        event_type: "feeds.feed_click",
        payload: {
          feed_card: feed_item&.analytics_attributes,
        }
      }
    ))
  end

  # Public: Returns a link to a release
  #
  # title - A String of the title of the release to display
  # release - A Release to link to
  # feed_item: Conduit::FeedItem - with release
  # system_arguments - A Hash of [system arguments](https://primer.style/view-components/system-arguments) to pass to the link
  def link_to_feed_release(
    title,
    release,
    feed_item,
    **system_arguments
  )
    return unless title && release && feed_item

    render(Primer::Beta::Link.new(
      href: release_path(release),
      data: feed_clicks_hydro_attrs(click_target: "release_link", feed_item: feed_item),
      scheme: :primary,
      underline: false,
      font_weight: :bold,
      **system_arguments
    )) { h(title) }
  end

  def link_to_feed_releases(
    title,
    repository,
    feed_item,
    **system_arguments
  )
    return unless title && repository && feed_item

    render(Primer::Beta::Link.new(
      href: releases_path(repository),
      data: feed_clicks_hydro_attrs(click_target: "releases_link", feed_item: feed_item),
      underline: false,
      **system_arguments
    )) { h(title) }
  end

  def feed_pull_request_link_data(pull_request:, click_target: "pull_request_link", feed_item:)
    feed_clicks_hydro_attrs(
      click_target: click_target,
      feed_item: feed_item
    ).merge(hovercard_data_attributes_for_issue_or_pr(pull_request))
  end

  def feed_issue_link_data(issue:, click_target: "issue_link", feed_item:)
    feed_clicks_hydro_attrs(
      click_target: click_target,
      feed_item: feed_item
    ).merge(hovercard_data_attributes_for_issue_or_pr(issue))
  end

  def feed_pull_request_comment_link_data(pull_request:, comment:, click_target: "pull_request_link", feed_item:)
    feed_clicks_hydro_attrs(
      click_target: click_target,
      feed_item: feed_item
    ).merge(hovercard_data_attributes_for_issue_or_pr(pull_request, comment_id: comment.id, comment_type: "issue_comment"))
  end

  def feed_issue_comment_link_data(issue:, comment:, click_target: "issue_link", feed_item:)
    feed_clicks_hydro_attrs(
      click_target: click_target,
      feed_item: feed_item
    ).merge(hovercard_data_attributes_for_issue_or_pr(issue, comment_id: comment.id, comment_type: "issue_comment"))
  end

  # title: string
  # feed_item: Conduit::FeedItem
  def link_to_feed_pull_request(
    title,
    pull_request,
    feed_item,
    **system_arguments
  )
    return unless title && pull_request && feed_item

    render(Primer::Beta::Link.new(
      href: pull_request.path_uri.to_s,
      data: feed_clicks_hydro_attrs(click_target: "pull_request_link", feed_item: feed_item),
      scheme: :primary,
      underline: false,
      font_weight: :bold,
      **system_arguments
    )) { h(title) }
  end

  def link_to_feed_repository_discussions(title, repository, feed_item)
    render(Primer::Beta::Link.new(
      href: "#{repository.path_uri}/discussions",
      data: feed_clicks_hydro_attrs(click_target: "discussion_link", feed_item: feed_item),
      scheme: :primary,
      underline: false,
      font_weight: :bold,
    )) { h(title) }
  end

  # Public: Returns a hash of attributes to be passed as `data` attributes or `hydro_data` where available in order to track clicks on a feed item
  #
  # click_target - A String representing where the click originated from
  # feed_item  - Conduit::FeedItem to provide analytics data
  # metadata   - lib/hydro/schemas/github/feeds/v0/entities/feed_metadata_pb.rb
  #            - contains applied filter groups, filter values
  def feed_clicks_hydro_attrs(click_target:, feed_item: nil, metadata: {})
    payload = {
      click_target: click_target,
      feed_card: feed_item&.analytics_attributes,
      original_request_id: feed_item&.request_id,
    }

    payload[:metadata] = metadata if metadata.present?

    hydro_attrs = hydro_click_tracking_attributes("feeds.feed_click", payload)

    feeds_click_dev_attributes(hydro_attrs, click_target: click_target, resource_type: feed_item&.resource_type, metadata: metadata)
  end

  # Public: Returns a hash of attributes to be passed as `data` attributes or `hydro_data` where available in order to track views on a feed item
  #
  # feed_item - Conduit::FeedItem to provide analytics data
  def feed_view_hydro_attrs(feed_item:)
    payload = {
      feed_card: feed_item.analytics_attributes,
      original_request_id: feed_item.request_id,
    }
    hydro_view_tracking_attributes("feeds.feed_visible", payload)
  end

  # Public: Adds analytics info to display for clickable items
  def feeds_click_dev_attributes(attrs, **data)
    if current_user&.feature_enabled?(:feeds_dev_analytics)
      attrs["feeds-analytics"] = data.compact_blank
    end

    attrs
  end

  # Public: Returns a hash of attributes to be passed as `data` attributes to provide hovercard behavior for a user or organization
  #
  # user - A User or Organization to provide hovercard data for
  # url_params (optional) - A Hash of parameters to pass to the hovercard to place parameters in the request url
  def hovercard_attrs_for_user(user, url_params: {})
    attrs = case user
    when Organization, PlatformTypes::Organization
      hovercard_data_attributes_for_org(login: user.display_login, tracking: true, url_params: url_params)
    else
      hovercard_data_attributes_for_user(user, tracking: true, url_params: url_params)
    end
  end

  def link_to_feed_commit_sha(sha:, repo:, feed_item:, data: {}, **system_arguments)
    return unless sha && repo && feed_item

    commit_url = commit_path(sha, repo)
    metadata = {
      clicked_resource_type: Conduit::AnalyticsHelper::ResourceType::PUSH_EVENT,
      clicked_resource_id: feed_item&.subject&.id,
    }
    data.merge!(feed_clicks_hydro_attrs(
      click_target: "commit_link",
      feed_item: feed_item,
      metadata: metadata,
    ))
    data.merge!(hovercard_data_attributes_for_commit(commit_url: commit_url))

    render(Primer::Beta::Link.new(
      href: commit_url,
      data: data,
      scheme: :primary,
      underline: false,
      font_weight: :bold,
      **system_arguments
    )) { sha.first(7) }
  end

  def link_to_feed_branch(branch_name:, repo:, feed_item:, data: {}, **system_arguments)
    return unless branch_name && repo && feed_item

    branch_url = tree_path("", branch_name, repo)
    metadata = {
      clicked_resource_type: Conduit::AnalyticsHelper::ResourceType::PUSH_EVENT,
      clicked_resource_id: feed_item&.subject&.id,
    }
    data.merge!(feed_clicks_hydro_attrs(
      click_target: "branch_link",
      feed_item: feed_item,
      metadata: metadata,
    ))

    render(Primer::Beta::Link.new(
      href: branch_url,
      data: data,
      scheme: :primary,
      underline: false,
      **system_arguments
    )) { branch_name }
  end

  def link_to_feed_push_comparison(text:, url:, feed_item:, data: {}, **system_arguments)
    return if text.blank? || url.blank? || feed_item.blank?

    metadata = {
      clicked_resource_type: Conduit::AnalyticsHelper::ResourceType::PUSH_EVENT,
      clicked_resource_id: feed_item&.subject&.id,
    }
    data.merge!(feed_clicks_hydro_attrs(
      click_target: "comparison_link",
      feed_item: feed_item,
      metadata: metadata,
    ))

    render(Primer::Beta::Link.new(
      href: url,
      data: data,
      scheme: :primary,
      underline: false,
      **system_arguments
    )) { text }
  end

  private

  # Private: Provides a url to the user's profile based on whether the user is an organization or a user
  def url_for_user(user)
    url = case user
    when Business
      enterprise_path(user)
    else
      user_path(user)
    end
    url
  end
end
