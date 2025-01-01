# typed: true
# rubocop:disable Primer/PrimerOcticon
# frozen_string_literal: true

module DiscussionsHelper
  extend T::Helpers

  include ApplicationHelper
  include CachedOcticonHelper
  include CurrentRepositoryInteractionsHelper
  include EmojiHelper
  include GitHub::Memoizer
  include OcticonsHelper

  abstract!

  requires_ancestor { ActionView::Base }

  sig { abstract.returns(T.nilable(Repository)) }
  def current_repository; end

  sig { abstract.returns(T::Boolean) }
  def logged_in?; end

  sig { abstract.returns(T.nilable(User)) }
  def current_user; end

  sig { abstract.returns(T::Boolean) }
  def site_admin?; end

  sig { abstract.returns(T::Boolean) }
  def is_org_level?; end

  # Used with `hydro.schemas.github.v1.DiscussionClick` event
  DISCUSSION_CLICK_EVENT_CONTEXTS = [
    :EVENT_CONTEXT_UNKNOWN,
    :DISCUSSIONS_LIST,
    :DISCUSSION_VIEW,
    :NEW_DISCUSSION_VIEW,
  ].freeze

  # Used with `hydro.schemas.github.v1.DiscussionClick` event
  DISCUSSION_CLICK_EVENT_TARGETS = [
    :EVENT_TARGET_UNKNOWN,
    :DISCUSSION_LINK,
    :USER_PROFILE_LINK,
    :NEW_DISCUSSION_LINK,
    :COPY_LINK_MENU_ITEM,
    :QUOTE_REPLY_MENU_ITEM,
    :REFERENCE_IN_NEW_ISSUE_MENU_ITEM,
    :REPORT_CONTENT_MENU_ITEM,
    :COMMUNITY_LINK,
  ].freeze

  # Cap the number of participant avatars displayed in the Discussion index
  DISCUSSION_MAX_DISPLAYED_AVATARS = 3

  def discussion_category_emoji_tag(discussion_category, classes: nil)
    emoji = emoji_for(discussion_category.emoji)
    if emoji
      emoji_tag(emoji, class: classes)
    else
      octicon("comment-discussion")
    end
  end

  # org_param - the display_login of the Organization to use in routing, if working with org-level discussions
  def discussions_list_path(org_param: nil, **args)
    if current_repository || args.has_key?(:repository)
      repo = args.delete(:repository) || current_repository
      if args.has_key?(:category_slug) && org_param.present?
        org_discussions_category_path(repo.owner_display_login, args)
      elsif args.has_key?(:category_slug)
        category_discussions_path(repo.owner_display_login, repo.name, args)
      else
        agnostic_discussions_path(repo, org_param: org_param, **args)
      end
    elsif respond_to?(:this_organization) && T.unsafe(self).this_organization
      org_discussions_path(T.unsafe(self).this_organization, args)
    else
      all_discussions_path(args)
    end
  end

  # Public: Build a discussions search path, including generating category vanity URLs when appropriate.
  #
  # replace - Hash of values to override in the current search query
  # category_override - replace all category components with one instance of this override value
  # org_param - the display_login of the Organization to use in routing, if working with org-level discussions
  #
  # Examples
  #
  #   # Given discussions_q value of "author:iancanderson"
  #   discussions_search_path(replace: { author: "cheshire137" })
  #   # => "/:owner/:repo/discussions?discussions_q=author:cheshire137"
  #
  #   discussions_search_path(replace: { author: nil })
  #   # => "/:owner/:repo/discussions"
  #
  #   # Given discussions_q value of "category:fun"
  #   discussions_search_path(replace: { category: "boring" })
  #   # => "/:owner/:repo/discussions/categories/boring"
  #
  #   discussions_search_path(append: ["abc def"])
  #   # => "/:owner/:repo/discussions/categories/fun?discussions_q=category:fun%20abc%20def"
  #
  #   discussions_search_path(category_override: "boring")
  #   # => "/:owner/:repo/discussions?discussions_q=category:boring"
  #
  # Returns a String relative path
  def discussions_search_path(
    delete: [],
    replace: {},
    category_override: nil,
    created_override: nil,
    append: [],
    discussions_query: [],
    repository: nil,
    query_params: {},
    allow_blank: false,
    org_param: nil
  )
    query_components = discussions_search_query(delete: delete, replace: replace, category_override: category_override,
      created_override: created_override, append: append, discussions_query: discussions_query)
    query_str = Search::Queries::DiscussionQuery.stringify(query_components)

    category_terms = query_components.select { |term| term.try(:first) == :category }
    if category_terms.one?
      query_params[:category_slug] = DiscussionCategory.slug_for_name(category_terms.first.second)
      if query_components.size > 1
        query_params[:discussions_q] = query_str
      end
    elsif query_str.present?
      query_params[:discussions_q] = query_str
    end

    if repository
      query_params[:repository] = repository
    end

    if query_params[:discussions_q].nil? && allow_blank
      query_params[:discussions_q] = ""
    end

    discussions_list_path(org_param: org_param, **query_params)
  end

  def discussions_search_query(delete: [], replace: {}, category_override: nil, created_override: nil, append: [], discussions_query: T.unsafe(self).parsed_discussions_query)
    components = discussions_query.dup
    replace.each_pair do |replace_key, replace_val|

      case replace_val
      when NilClass
        components.reject! { |comp_key, _| comp_key == replace_key }
      when Hash
        components.reject! do |comp_key, comp_val|
          next unless comp_key == replace_key
          next unless replace_val.one?
          replace_val.keys.first == comp_val && replace_val.values.first.nil?
        end
      else
        components << [replace_key, replace_val]
      end
    end

    components += append
    components -= delete

    if category_override.present?
      components.reject! { |comp_key, _| comp_key == :category }
      components << [:category, category_override]
    end

    if created_override.present?
      components.reject! { |comp_key, _| comp_key == :created }
      components << [:created, created_override]
    end

    # Search::Queries::DiscussionQuery.stringify(components.uniq).presence
    components.uniq
  end

  def discussion_icon(discussion)
    options = if discussion.closed?
      reason = discussion_state_reasons_by_value[discussion.state_reason]
      { icon: reason.octicon, color: reason.octicon_color }
    else
      { icon: :"comment-discussion" }
    end

    render(Primer::Beta::Octicon.new(**options))
  end

  def safe_new_discussion_click_attrs(target:)
    safe_data_attributes(new_discussion_click_attrs(target: target))
  end

  def new_discussion_click_attrs(target:)
    discussion_click_attrs(nil, event_context: :NEW_DISCUSSION_VIEW, target: target)
  end

  # Public: Get HTML-safe Hydro `data` attributes for clicking something on the discussions
  # index page.
  #
  # discussion_or_comment - a Discussion or DiscussionComment; optional
  # target - a Symbol from the `DISCUSSION_CLICK_EVENT_TARGETS` list representing
  #          what was clicked
  #
  # Returns a String.
  def safe_discussions_list_click_attrs(discussion_or_comment, target:)
    safe_data_attributes(discussions_list_click_attrs(discussion_or_comment, target: target))
  end

  # Public: Get Hydro `data` attributes for clicking something on the discussions index page.
  #
  # discussion_or_comment - a Discussion or DiscussionComment; optional
  # target - a Symbol from the `DISCUSSION_CLICK_EVENT_TARGETS` list representing
  #          what was clicked
  #
  # Returns a Hash.
  def discussions_list_click_attrs(discussion_or_comment, target:)
    discussion_click_attrs(discussion_or_comment, event_context: :DISCUSSIONS_LIST, target: target)
  end

  # Public: Get Hydro `data` attributes for clicking something on an individual discussion page.
  #
  # discussion_or_comment - a Discussion or DiscussionComment
  # target - a Symbol from the `DISCUSSION_CLICK_EVENT_TARGETS` list representing
  #          what was clicked
  #
  # Returns a Hash.
  def discussion_view_click_attrs(discussion_or_comment, target:)
    discussion_click_attrs(discussion_or_comment, event_context: :DISCUSSION_VIEW, target: target)
  end

  # Public: Get Hydro `data` attributes for clicking something discussion-related.
  #
  # discussion_or_comment - a Discussion or DiscussionComment; optional
  # event_context - a Symbol from the `DISCUSSION_CLICK_EVENT_CONTEXTS` list representing
  #                 where on the site the click happened
  # target - a Symbol from the `DISCUSSION_CLICK_EVENT_TARGETS` list representing
  #          what was clicked
  #
  # Returns a Hash.
  def discussion_click_attrs(discussion_or_comment, event_context: :EVENT_CONTEXT_UNKNOWN, target: :EVENT_TARGET_UNKNOWN)
    unless DISCUSSION_CLICK_EVENT_CONTEXTS.include?(event_context)
      raise ArgumentError, "invalid discussion click event context '#{event_context}'"
    end

    unless DISCUSSION_CLICK_EVENT_TARGETS.include?(target)
      raise ArgumentError, "invalid discussion click event target '#{target}'"
    end

    data = {
      event_context: event_context,
      target: target,
      current_repository_id: current_repository&.id,
      discussion_repository_id: discussion_or_comment&.repository_id,
      org_level: params.has_key?(:org)
    }

    if discussion_or_comment
      data[:discussion_id] = discussion_or_comment.discussion_id
      data[:discussion_comment_id] = discussion_or_comment.discussion_comment_id
    end

    hydro_click_tracking_attributes("discussions.click", data)
  end

  # org_param - the display_login of the Organization to use in routing, if working with org-level discussions
  def discussion_timeline_comment_url(discussion_or_comment, timeline:, org_param: nil)
    if discussion_or_comment.is_a?(DiscussionComment)
      agnostic_discussion_url(timeline.discussion, org_param: org_param, anchor: discussion_or_comment.dom_id)
    else
      agnostic_discussion_url(discussion_or_comment, org_param: org_param)
    end
  end

  # Discussion page <title>. This is "<user>/<repo> · Discussions · GitHub" for index pages
  # or "<user>/<repo> <category> · Discussions · GitHub" for index with a category selected.
  # or "<discussion.title> · <user>/<repo> · Discussion #<discussion_number>" for individual discussion pages.
  # We exclude the `· GitHub` part for logged out users, since we add that to the end for all logged out pages already.
  #
  # You can set the `remove_separator` argument to true to remove the `/` in the nwo. We want to do this when
  # being crawled by robots for SEO reasons.
  def discussion_page_title(discussion = nil, category_slug = nil, remove_separator: false)
    owner_title = is_org_level? ? T.unsafe(self).this_organization.login : current_repository&.name_with_display_owner

    if remove_separator && !is_org_level?
      owner_title = owner_title.gsub("/", " ")
    end

    [
      (discussion.title if discussion),
      (category_slug ? "#{owner_title} #{category_slug.titleize}" : owner_title),
      (discussion ? "Discussion ##{discussion.number}" : "Discussions"),
      ("GitHub" if !discussion && logged_in?)
    ].compact.join(" · ")
  end

  def discussion_page_description(discussion = nil, category_slug = nil)
    owner_title = if is_org_level?
      T.unsafe(self).this_organization.login
    else
      (current_repository&.name_with_display_owner || "").gsub("/", " ")
    end
    if !discussion && !category_slug
      "Explore the GitHub Discussions forum for #{owner_title}. Discuss code, ask questions & collaborate with the developer community."
    elsif category_slug
      "Explore the GitHub Discussions forum for #{owner_title} in the #{category_slug.titleize} category."
    end
  end

  def mark_comments_as_unread!
    content_for(:unread_comment_class, " js-unread-item will-transition-once unread-item")
  end

  def unread_comment_class
    content_for(:unread_comment_class) || ""
  end

  def hydro_discussions_filter_tracking_data(filter:, sort:)
    hydro_click_tracking_attributes("discussions.apply_filter",
      repository_id: current_repository&.id,
      sort: sort,
      filter: filter,
    )
  end

  def discussion_social_count(n)
    return "0" if n == 0

    power = 3 * (Math.log10(n) / 3).floor

    prefixes = {
      3 => "k",
      6 => "m",
      9 => "b",
      12 => "t",
    }

    return "#{n}" unless prefixes.keys.include?(power)

    "#{n / 10**power}#{prefixes[power]}"
  end

  def cached_primer_octicon(*args, **kwargs)
    key = [args, kwargs]
    DiscussionsCache.octicons ||= {}
    DiscussionsCache.octicons[key] ||= primer_octicon(*T.unsafe(args), **kwargs)
  end

  def cached_path(helper, *args, **kwargs)
    key = [helper, args, kwargs]
    DiscussionsCache.paths ||= {}
    DiscussionsCache.paths[key] ||= case helper
    when :discussions_badges_path
      discussions_badges_path(*T.unsafe(args), **kwargs)
    when :reactions_discussion_path
      reactions_discussion_path(*T.unsafe(args), **kwargs)
    when :discussions_votes_path
      discussions_votes_path(*T.unsafe(args), **kwargs)
    when :discussions_path
      discussions_path(*T.unsafe(args), **kwargs)
    end
  end

  def cached_emoji_tag(*args, **kwargs)
    key = [args, kwargs]
    DiscussionsCache.emojis ||= {}
    DiscussionsCache.emojis[key] ||= emoji_tag(*T.unsafe(args), **kwargs)
  end

  class DiscussionsCache < ActiveSupport::CurrentAttributes
    attribute :paths, :octicons, :emojis
  end

  private

  memoize def discussion_state_reasons_by_value
    Closables::BaseComponent::DISCUSSION_REASONS.index_by(&:value)
  end
end
