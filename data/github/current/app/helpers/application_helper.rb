# typed: false
# rubocop:disable Primer/PrimerOcticon
# frozen_string_literal: true

module ApplicationHelper
  include ActionView::Helpers::NumberHelper
  include BasicHelper, EscapeHelper, UrlHelper, MoneyHelper, OcticonsHelper, Primer::ViewHelper, Primer::FormHelper
  include HovercardHelper
  include AnalyticsHelper
  include StaticAssetHelper
  include HawaiiExperimentHelper

  REQUEST_RENDER_ALLOWED_TAGS = %w[
      action context_region_type controller event force_pulls
      from has_assignee_filter has_author_filter has_closed_filter
      has_label_filter has_milestone_filter has_open_filter
      has_project_filter has_review_filter has_sort_filter header_redesign
      is_default_query is_empty is_self_assigned is_self_authored
      logged_in partial range repo_debug host]

  # Returns a String HTML link to switch runtime environments.
  def runtime_switcher_link
    if !Rails.env.development?
      fail "runtime switching is only allowed in development"
    end

    runtime = GitHub.runtime.opposite_runtime
    link_to content_tag(:span, runtime), "/?_runtime=#{runtime}"
  end

  # Deprecated: prefer current_copilot_user_v2
  def current_copilot_user
    if self.class < ApplicationController
      # If ApplicationHelper was included in a controller class, just call the existing #current_copilot_user method
      # that's included in all controllers:
      super
    else
      controller.current_copilot_user
    end
  end

  def current_copilot_user_v2
    if self.class < ApplicationController
      # If ApplicationHelper was included in a controller class, just call the existing #current_copilot_user method
      # that's included in all controllers:
      super
    else
      controller.current_copilot_user_v2
    end
  end

  # Produces an html breadcrumb with each crumb linked, based on a blob or
  # tree's path in a repo.
  #
  # For example this:
  #   hector/lib/hector.rb
  #
  # Becomes something like:
  #   <a>hector</a> / <a>lib</a> / hector.rb
  #
  # path (required) - path to convert to breadcrumbs as an Array of Strings, split on '/'.
  #                   Example: ["hector", "lib", "hector.rb"]
  #
  # options (Hash)
  #
  # label         - An optional String that explains the page,
  #                 e.g. 'Commit History'
  # linker        - The URL helper to use to link to each crumb.
  #                 Defaults to `tree_path`.
  # linkify_last  - Whether to link the last part of the path
  #                 Defaults to false
  #
  # Returns an HTML safe String
  def breadcrumb_trail(path, opts = {})
    label = opts[:label]
    linker = opts[:linker] || :tree_path
    linkify_last = opts[:linkify_last]
    hide_filename = opts[:hide_filename]
    hide_root = opts[:hide_root]
    separator_class = opts[:separator_class] || "separator"
    turbo_frame = opts.fetch(:turbo_frame, nil)

    ref = tree_name
    link_opts = { class: nil }

    if turbo_frame.present?
      link_opts["data-turbo-frame"] = turbo_frame
    end
    link_opts[:rel] = "nofollow" if ref == commit_sha

    root = breadcrumb_segment(current_repository.name, send(linker, "", ref), link_opts)
    outs = []

    outs << content_tag(:span, root, class: "js-repo-root text-bold") unless hide_root

    Array(path).each_with_index do |segment, i|
      if i == path.size - 1 && !linkify_last
        segment = content_tag(:strong, scrubbed_utf8(segment), class: "final-path")
      else
        segment = breadcrumb_segment(scrubbed_utf8(segment), send(linker, path[0..i], ref), link_opts)
      end
      outs << segment unless hide_filename && i == path.size - 1
    end

    outs << label if label
    outs << "" if (outs.length == 1 && !hide_root) || linkify_last || hide_filename
    safe_join(outs, content_tag(:span, "/", class: separator_class))
  end

  def breadcrumb_segment(text, link, link_opts)
    text = content_tag(:span, text)
    link = link_to(text, link, link_opts)
    span = content_tag(:span, link, { class: "js-path-segment d-inline-block wb-break-all" })
  end

  def discover_commits_feed
    tree_name = tree_name_for_display
    discover_feed "Recent Commits to #{current_repository}:#{tree_name}",
      tokenized_feed_url(commits_feed_url(name: tree_name))
  end

  def discover_feed(title, url)
    options = {
      href: url,
      rel: "alternate",
      title: title,
      type: "application/atom+xml",
    }
    tag(:link, options, open = true)
  end

  def user_for_email(email)
    # Don't try to match up commits that use generic domains.
    return if UserEmail.generic_domain? email

    # try using the mass find committers hash
    user = @commits && committers[email]
    return user if user

    # fall back to memoized list of users loaded from email
    @user_for_email ||= {}
    if @user_for_email.key?(email)
      @user_for_email[email]
    elsif defined?(current_repository) && current_repository&.is_enterprise_managed?
      @user_for_email[email] = User.find_by_email(email, business: current_repository&.enterprise_managed_business)
    else
      @user_for_email[email] = User.find_by_email(email)
    end
  end

  # Link to an author's user page on github, or write the author's name if no
  # user exists for the author's email.
  #
  # author  - A User or anything that responds to #email, or a string
  #           author name.
  # options - The :truncate option can be used to truncate text content.
  #
  # Returns HTML content wrapped in an <a> or <span> depending on whether a
  # user exists for the author.
  def link_author(author, options = {})
    if author.is_a?(User)
      profile_link(author, options)
    elsif author.respond_to?(:user) && author.user
      profile_link(author.user, options)
    elsif !author.respond_to?(:user) &&
          author.respond_to?(:email) && !author.email.blank? &&
          user = user_for_email(author.email)
      profile_link(user, options)
    else
      span_class = "tooltipped #{options[:class]}"
      if author.to_s.blank?
        content_tag :span, "Unknown", :class => span_class, "aria-label" => "Oops! This commit is missing author information."
      elsif options[:truncate] && author.to_s.size > 15
        content_tag :span, truncate(author.to_s, length: 15), :class => span_class, "aria-label" => h(author.to_s)
      else
        author.to_s
      end
    end
  end

  # Link to an actor's profile page on github
  #
  # Includes hovercards where applicable
  #
  # actor  - A User, Organization, or Business
  #
  # options - The :truncate option can be used to truncate text content.
  #           The :show_full_name option can be used to show comment authors full name if present
  #           The :skip_hovercard option can be used to not have a hovercard for that link
  #           The :skip_hovercard_tracking option can be used to render a hovercard without tracking info
  #           The :hydro_data option can be used to pass Hydro tracking attributes for the link
  #
  # Returns HTML content wrapped in an <a>
  def profile_link(actor, options = {}, &block)
    return if actor.nil?

    options[:data] ||= {}

    if hydro_data = options.delete(:hydro_data)
      options[:data] = options[:data].merge(hydro_data)
    end

    unless options.delete(:skip_hovercard)
      skip_tracking = options.delete(:skip_hovercard_tracking)
      hovercard_attributes = \
        case actor
        when Organization
          hovercard_data_attributes_for_org(login: actor.display_login, tracking: !skip_tracking)
        when Bot
          hovercard_data_attributes_for_bot(actor, tracking: !skip_tracking)
        when User
          hovercard_data_attributes_for_user(actor, tracking: !skip_tracking)
        else
          {}
        end

      options[:data] = options[:data].merge hovercard_attributes
    end

    url = options.delete(:url) || path_for(actor)

    if block_given?
      link_to url, options, &block
    else
      if options[:show_full_name] && actor.profile_name.present? && !actor.is_a?(Bot)
        link_to(actor.display_login_legacy, url, options).concat(
          content_tag(:span, class: "css-truncate expandable") do
            content_tag(
              :span,
              "(#{actor.profile_name.strip})",
              class: "css-truncate-target text-normal ml-1",
              data: test_selector_hash("commenter-full-name"),
              style: "max-width:175px;",
            )
          end,
        )
      elsif options[:show_full_name_only] && actor.profile_name.present? && !actor.is_a?(Bot)
        link_to actor.profile_name.strip, url, options
      else
        link_to display_name_for_actor(actor), url, options
      end
    end
  end

  def path_for(actor)
    if actor.is_a? Business
      enterprise_path(actor)
    else
      user_path(actor)
    end
  end

  module AuthenticationClick
    module AuthenticationType
      LOG_IN = :LOG_IN
      SIGN_UP = :SIGN_UP
    end
  end

  def sign_in_link_data_attributes(location_in_page:, repository_id: nil)
    hydro_click_tracking_attributes("authentication.click",
                                    location_in_page: location_in_page,
                                    repository_id: repository_id,
                                    auth_type: AuthenticationClick::AuthenticationType::LOG_IN)
  end

  def sign_up_link_data_attributes(location_in_page:, repository_id: nil)
    hydro_click_tracking_attributes("authentication.click",
                                    location_in_page: location_in_page,
                                    repository_id: repository_id,
                                    auth_type: AuthenticationClick::AuthenticationType::SIGN_UP)
  end

  # Link to an actor's profile page on github with their avatar image
  #
  # Includes hovercards where applicable
  #
  # user  - A User
  #
  # options - The :img_class option can be used to set css class(es) on the <img>
  #           The :link_class option can be used to set css class(es) on the <a>
  #           The :url option can be used to override the URL of the <a>
  #           The :link_data option can be used to to set data attributes on the <a>
  #           The :target option can be set to "_blank" to open the link in a new tab
  #
  # Returns avatar <img> wrapped in an <a>
  def linked_avatar_for(user, size, img_class: nil, link_class: "d-inline-block", url: nil, link_data: nil, target: nil)
    profile_link(user, class: link_class, url: url, data: link_data, target: target) do
      avatar_for(user, size, class: img_class)
    end
  end

  # Find what type of user the commiter is
  #
  # user - The user we are testing
  #
  # returns a string (author or contributor)
  def find_rel_type(user, repo = nil)
    target_repo = repo || (defined?(current_repository) && current_repository)
    if target_repo && target_repo.owner == user
      "author"
    else
      "contributor"
    end
  end

  def page_title(*args)
    if title = args.first
      @page_title = title.dup.force_encoding("UTF-8").scrub!
    else
      "#{@page_title} · GitHub"
    end
  end

  def full_page_title(title)
    @full_title = title
  end

  def page_info(info = {})
    @html_class ||= info[:html_class]
    @page_title ||= info[:title].dup.force_encoding("UTF-8").scrub! if info[:title]
    @page_breadcrumb ||= info[:breadcrumb].dup.force_encoding("UTF-8").scrub! if info[:breadcrumb]
    @page_breadcrumb_object ||= info[:breadcrumb_object] if info[:breadcrumb_object]
    @page_breadcrumb_owner ||= info[:breadcrumb_owner] if info[:breadcrumb_owner]
    @force_compact_header ||= info[:force_compact_header]
    @page_class ||= info[:class]
    @header_class ||= info[:header_class]
    @selected_link ||= info[:selected_link]
    @sidebar ||= info[:sidebar]
    @hide_subnav ||= info[:hide_subnav] == true
    @hide_footer ||= (info[:footer] == false || info[:hide_footer] == true)
    @hide_flash ||= info[:hide_flash] == true
    @hide_header ||= info[:hide_header] == true
    @hide_header_content ||= info[:hide_header_content] == true
    @hide_search ||= info[:hide_search]
    @skip_pjax_container ||= info[:skip_pjax_container]
    @page_description ||= info[:description]
    @marketing_page_theme ||= info[:marketing_page_theme]
    @revenue_play ||= info[:revenue_play]
    @locale ||= info[:locale] || I18n.locale
    @marketing_footer_theme ||= info[:marketing_footer_theme]
    @container_xl ||= info[:container_xl]
    @container_full ||= info[:container_full]
    @page_responsive = defined?(@page_responsive) ? @page_responsive : set_page_responsive(info[:responsive])
    @page_sticky_footer ||= info[:sticky_footer]
    @skip_responsive_padding ||= info[:skip_responsive_padding]
    @page_full_height ||= info[:full_height]
    @page_full_height_scrollable ||= info[:full_height_scrollable]
    @dashboard_pinnable_item_id ||= info[:dashboard_pinnable_item_id]
    if @page_description.html_safe?
      @page_description = strip_tags(@page_description)
    end
    @page_richweb ||= info[:richweb]
    @hide_marketplace_retargeting_notice ||= info[:hide_marketplace_retargeting_notice]
    @hide_marketplace_pending_installations_notice ||= info[:hide_marketplace_pending_installations_notice]
    @show_repository_header_placeholder ||= info[:show_repository_header_placeholder]
    @noindex ||= info[:noindex]
    @noindex_and_nofollow ||= info[:noindex_and_nofollow]
    @canonical_url ||= info[:canonical_url]

    if logged_in? && current_user.site_admin?
      # Don't use ||= here, we want to overwrite the value
      @stafftools_link = info[:stafftools] if info[:stafftools]
      if current_repository && !@stafftools_link
        @stafftools_link = gh_stafftools_repository_path current_repository
      end

      if defined?(this_user) && this_user.present?
        @spamurai_url = Spam.url_for_trust_safety_account_login(this_user.login)
        @spamurai_url = Spam.url_for_repo(this_user.login, current_repository) if current_repository
      end
    end
  end

  # The title for this page. Used by pjax and the application layout.
  # Changes based on whether you're logged in or not.
  # Use `page_title` to set the page title.
  #
  # Returns a String.
  def title_for_page
    if @page_title
      logged_in? ? @page_title.to_s : @page_title.to_s + " · GitHub"
    elsif @full_title
      @full_title.to_s
    else
      "GitHub · #{default_tagline}"
    end
  end

  def selected_link
    @selected_link
  end

  # Currently only used for Enterprise pages
  def sidebar
    @sidebar
  end

  def hide_subnav
    @hide_subnav
  end

  def marketing_footer_theme?
    @marketing_footer_theme.present?
  end

  def page_breadcrumb_object
    @page_breadcrumb_object
  end

  def page_breadcrumb_owner
    @page_breadcrumb_owner
  end

  def notification(text = nil)
    content_tag :div, text, class: :notification if text
  end

  def resolve_key_path(public_key)
    if current_repository
      deploy_key_path(current_repository.owner, current_repository, public_key)
    else
      public_key_path(public_key)
    end
  end

  def resolve_key_verify_path(public_key)
    if current_repository
      verify_deploy_key_path(current_repository.owner, current_repository, public_key)
    else
      verify_public_key_path(public_key)
    end
  end

  def resolve_ip_allowlist_entry_path(entry)
    case entry.owner
    when Organization
      organization_ip_allowlist_entry_path(entry.owner.display_login, entry.id)
    when Business
      enterprise_ip_allowlist_entry_path(entry.owner.slug, entry.id)
    when Integration
      if entry.owner.owner.organization?
        settings_org_apps_ip_allowlist_entry_path(entry.owner.owner.display_login, entry.owner.slug, entry.id)
      else
        settings_user_apps_ip_allowlist_entry_path(entry.owner.slug, entry.id)
      end
    end
  end

  def github_url
    request.protocol + GitHub.host_name
  end

  def enterprise_web_url(path = "")
    url = File.join(GitHub.enterprise_web_url, path)
    if hash = session[:utm_memo]
      query = hash.to_query
      delim = url.include?("?") ? "&" : "?"
      url + delim + query
    else
      url
    end
  end

  # Return the new Enterprise trial flow URL. Used on buttons for /business marketing pages.
  def ent_trial_url
    enterprise_web_url("/trial")
  end

  # Return the enterprise contact flow URL hosted on Dotcom. Used on buttons for /business marketing
  # pages.
  def ent_contact_url
    "#{github_url}/enterprise/contact"
  end

  # Public: Generates a styled "<< Previous | Next >>" paginator from a
  # WillPaginate collection.
  #
  # collection - A WillPaginate::Collection.
  # options    - Hash options passed to #raw_paginate.
  #              :prev_url       - String or Hash of URL options for the
  #                                Previous link.
  #              :next_url       - String or Hash of URL options for the Next
  #                                link.
  #              :previous_label - The String name of the Previous link.
  #              :next_label     - The String name of the Next link.
  #              :on_last_page   - Boolean that determines if we're on the last
  #                                page.
  #              :params         - Optional Hash of request parameters.  Uses
  #                                a Controller's parameters by default.
  #              :page_content   - Optional content to put between the next
  #                                and previous links. For example:
  #                                          << 2 of 24 pages >>
  #
  # Returns String HTML.
  def simple_paginate(collection, options = {})
    # Support collections that don't necessarily know the `total_entries` count
    size = collection.size + (collection.current_page - 1) * collection.per_page
    size += 1 if collection.next_page
    raw_paginate(size, collection.per_page, collection.current_page, options)
  end

  # Public: Generates a styled "<< Previous | Next >>" paginator.
  #
  # size         - Integer total entries.
  # per_page     - Integer limit.
  # current_page - Integer page number.
  # options      - Hash options passed to #raw_paginate.
  #                :prev_url       - String or Hash of URL options for the
  #                                  Previous link.
  #                :next_url       - String or Hash of URL options for the Next
  #                                  link.
  #                :previous_label - The String name of the Previous link.
  #                :next_label     - The String name of the Next link.
  #                :on_last_page   - Boolean that determines if we're on the
  #                                  last page.
  #                :params         - Optional Hash of request parameters.  Uses
  #                                  a Controller's parameters by default.
  #                :page_content   - Optional content to put between the next
  #                                  and previous links. For example:
  #                                            << 2 of 24 pages >>
  #                :class          - Optional class for pagination container.
  #                :next_index     - Optional Integer index of the first tag on the next page
  # Returns String HTML.
  def raw_paginate(size, per_page, current_page, options = {})
    return if current_page == 1 && size <= per_page

    original_params = options.delete(:params) || params.dup.permit!.to_hash.with_indifferent_access

    if options.has_key?(:param_name)
      prev_url = options.delete(:prev_url) || original_params.merge(options[:param_name] => current_page - 1)
      next_url = options.delete(:next_url) || original_params.merge(options[:param_name] => current_page + 1)
    else
      prev_url = options.delete(:prev_url) || original_params.merge(page: current_page - 1)
      next_url = options.delete(:next_url) || original_params.merge(page: current_page + 1)
    end

    previous_label = options.delete(:previous_label) || I18n.translate("will_paginate.previous_label")
    next_label     = options.delete(:next_label) || I18n.translate("will_paginate.next_label")

    links = []

    if show_previous_page_link?(current_page, per_page, options)
      links << link_to(previous_label, safe_url_for(prev_url), rel: "nofollow")
    else
      links << content_tag(:span, previous_label, class: "disabled color-fg-muted")
    end

    # Optional inner content between the previous/next links
    if options[:page_content]
      links << options.delete(:page_content)
    end

    if show_next_page_link?(size, per_page, current_page, options)
      links << link_to(next_label, safe_url_for(next_url), rel: "nofollow")
    else
      links << content_tag(:span, next_label, class: "disabled color-fg-muted")
    end

    content_tag :div, safe_join(links), class: options.fetch(:class, "pagination")
  end

  def show_batched_suggested_changes_onboarding_prompt?
    return @show_batched_suggested_changes_onboarding_prompt if defined? @show_batched_suggested_changes_onboarding_prompt

    @show_batched_suggested_changes_onboarding_prompt = logged_in? && !current_user.dismissed_notice?("batched_suggested_changes_onboarding_prompt")
  end

  def previous_cursor_url(page_info, action: nil, previous_param: :before, next_param: :after)
    previous_url = cursor_pagination_params(action: action, previous_param: previous_param, next_param: next_param)
    previous_url[previous_param] = page_info.start_cursor
    safe_url_for(previous_url)
  end

  def next_cursor_url(page_info, action: nil, previous_param: :before, next_param: :after)
    next_url = cursor_pagination_params(action: action, previous_param: previous_param, next_param: next_param)
    next_url[next_param] = page_info.end_cursor
    safe_url_for(next_url)
  end

  def cursor_paginate(page_info, previous_label: nil, next_label: nil, action: nil, pjax: false, previous_param: :before, next_param: :after, next_hotkey: nil, previous_hotkey: nil)
    links = []

    link_attrs = { rel: "nofollow", class: "btn BtnGroup-item" }
    if pjax
      link_attrs["data-pjax"] = true
    end

    if previous_label
      if page_info.has_previous_page?
        previous_url = previous_cursor_url(page_info, action: action, previous_param: previous_param, next_param: next_param)

        previous_attrs = if previous_hotkey
          link_attrs.merge({ "data-hotkey": previous_hotkey })
        else
          link_attrs
        end

        links << link_to(previous_label, previous_url, previous_attrs)
      else
        links << content_tag(:button, previous_label, { class: "btn BtnGroup-item", disabled: true })
      end
    end

    if next_label
      if page_info.has_next_page?
        next_url = next_cursor_url(page_info, action: action, previous_param: previous_param, next_param: next_param)

        next_attrs = if next_hotkey
          link_attrs.merge({ "data-hotkey": next_hotkey })
        else
          link_attrs
        end

        links << link_to(next_label, next_url, next_attrs)
      else
        links << content_tag(:button, next_label, { class: "btn BtnGroup-item", disabled: true })
      end
    end

    content_tag :div, safe_join(links), { class: "BtnGroup", "data-test-selector": "pagination" }
  end

  def show_next_page_link?(size, per_page, current_page, options)
    if options.has_key?(:next_index)
      options[:next_index] < size && !options[:on_last_page]
    else
      size > per_page * current_page && !options[:on_last_page] && !at_pagination_limit?
    end
  end

  def show_previous_page_link?(current_page, per_page, options)
    if options.has_key?(:next_index)
      options[:next_index] > per_page
    else
      current_page > 1
    end
  end

  # Public: Generate mailto: link with obfuscated email as its contents.
  #
  # Manually mark link and content as HTML safe since we encode every character
  #
  # email   - String email used for mailto: target and contents
  # options - Hash to pass along to mail_to helper
  #
  # Returns HTML safe link tag.
  def obfuscated_mail_to(email, options = {})
    encoded_email = email.gsub(/[{}`^%#|]/, { "#" => "%23", "%" => "%25", "^" => "%5E", "`" => "%60", "{" => "%7B", "|" => "%7C", "}" => "%7D" })
    obfuscated_link = "mailto:#{obfuscate_str(encoded_email)}"
    obfuscated_email = obfuscate_str(email)
    link_to(obfuscated_email.html_safe, obfuscated_link.html_safe, options) # rubocop:disable Rails/OutputSafety
  end

  def link_selected?(link, options = {})
    # link is not selected if URI does not match all the params passed in :include_params option
    incl_params = options[:include_params]
    if !incl_params.nil? && incl_params.any?
      incl_params.each do |key, value|
        return false if request.query_parameters[key].nil? || request.query_parameters[key] != value
      end
    end

    # link is not selected if URI matches one of the params passed in :exclude_params option
    excl_params = options[:exclude_params]
    if !excl_params.nil? && excl_params.any?
      excl_params.each do |key, value|
        return false if !request.query_parameters[key].nil? && request.query_parameters[key] == value
      end
    end

    disqualifying_params = options[:disqualifying_params]
    if !disqualifying_params.nil? && disqualifying_params.any?
      disqualifying_params.each do |param_name|
        return false if request.query_parameters.has_key?(param_name)
      end
    end

    selected = (current_page?(link) || current_page?("#{link}/") || @selected_link == link)
    selected ||= select_highlight?(options[:selected_link] || @selected_link, options[:highlight])
  end

  def select_highlight?(selected, *highlight)
    Array(highlight).flatten.detect do |highlighted|
      selected == highlighted || current_page?(highlighted.to_s)
    end
  end

  # Generates a link_to, but with a class of selected if any of the
  # following conditions are met:
  #   1. The current page is the one being linked to
  #   2. @selected_link is equal to the one being linked to
  #   3. The current page is inside of the array passed to options[:highlight]
  #   4. @selected_link is inside of the array passed to options[:highlight]
  #   5. options[:selected_link] is inside of the array passed to options[:highlight]
  #
  # Accepts both short-hand and block-style helpers, similar to link_to:
  #
  #   <%= selected_link_to "testing", url %>
  #
  #   <% selected_link_to url do %>
  #     testing
  #   <% end %>
  def selected_link_to(text = nil, link = nil, options = nil, &block)
    if block_given?
      options = link
      link = text
      text = nil
    end
    options ||= {}

    selected = link_selected?(link, options)

    if selected
      options[:class] = "js-selected-navigation-item selected #{options[:class]}"
      options["aria-current"] = "page"
    else
      options[:class] = "js-selected-navigation-item #{options[:class]}"
    end

    options["data-selected-links"] = Array(options[:highlight]).join(" ") + " #{link}"
    options.delete(:highlight)

    tag = options.delete(:disabled) ? :span : :a
    options[:href] = link if tag == :a

    if block_given?
      content_tag(tag, capture(&block), options)
    else
      content_tag(tag, text, options)
    end
  end

  ALLOWED_FLASH_KEYS = %w( notice error message warn success).freeze

  # Get flash messages to present in global notice.
  #
  # Returns an Array of [type String, message String] objects.
  def global_flash
    flash.select do |type, message|
      ALLOWED_FLASH_KEYS.include?(type.to_s) && message.respond_to?(:to_str) && message.present?
    end.map do |type, message|
      [type, message]
    end
  end

  def packages_flash
    flash.select do |type, message|
      %w( packages_error).include?(type.to_s) && message.respond_to?(:to_str) && message.present?
    end.map do |type, message|
      [type, message]
    end
  end

  def budgets_flash
    flash.select do |type, message|
      %w( budgets_error budgets_notice).include?(type.to_s) && message.respond_to?(:to_str) && message.present?
    end.map do |type, message|
      [type, message]
    end
  end

  # Allow flash message to be moved in layout (i.e. session authentication)
  def flash_rendered!
    @flash_rendered = true
  end

  def flash_rendered?
    @flash_rendered
  end

  # Should the footer be shown?
  #
  # Returns true if the footer should be shown, false otherwise.
  def show_footer?
    !is_notifications?
  end

  # What should be shown as the title of the mark in the footer?
  #
  # Returns String
  def footer_mark_title
    extra = " #{GitHub.current_ref}" if GitHub.enterprise? && logged_in?
    "#{GitHub.flavor}#{extra}"
  end

  def is_notifications?
    params[:controller] == "newsies" && params[:action] == "index"
  end

  # Should the search bar and site nav be shown?
  #
  # Returns true if the search bar & site nav should be shown, false otherwise.
  def show_search_and_nav?
    !(params[:controller] == "generated_pages" && params[:action] == "themes")
  end

  def qr_code_generator(text)
    RQRCode::QRCode.new(text, level: :h)
  end

  class GitTemplateTimeout < StandardError; end

  # Wrapper around the most common use case for +rescue_with_timeout_partial+
  # to render our timeout partial.
  #
  # Takes a string partial and optional hash of local variables to pass.  If
  # a :style key is given in the locals, it will style the timeout div.
  def rescue_with_timeout_message(message = "This is taking too long to load!", locals = {}, &blk)
    rescue_with_timeout_partial("site/timeout", locals.merge(message: message), &blk)
  end

  # Rescue a block from timeouts and render a partial in the place of the
  # intended content.  Useful if you have long-running commit lists or file lists
  #
  # Takes a partial name and an optional hash of locals.
  def rescue_with_timeout_partial(partial_name, locals = {}, &blk)
    timeout = locals[:timeout] || GitHub.git_template_timeout
    GitHub::Timer.timeout(timeout, GitTemplateTimeout) do
      capture(&blk)
    end
  rescue ActionView::TemplateError, GitTemplateTimeout, GitRPC::Timeout, GitRPC::Failure, Timeout::Error => e
    if !timeout_error?(e)
      raise
    elsif (e.class != ActionView::TemplateError) || (e.cause.class == GitTemplateTimeout)
      Failbot.report_user_error(e)
      locals[:style] = "" unless locals[:style]
      render(partial: partial_name, locals: locals) # rubocop:disable GitHub/RailsViewRenderLiteral
    end
  end

  # Simulates a git operation timeout if +_timeout+ is set in the params. To
  # use it, add something like ?_timeout=1 to the end of the URL.
  def simulate_timeout_error_if_param!(klass_to_raise = Timeout::Error)
    raise klass_to_raise if params[:_timeout] && params[:_timeout] != "clear"
  end

  def attachments_enabled?
    GitHub.uploads_enabled?
  end

  # Public: Same as Rails' ActionView::Helpers::TextHelper#pluralize, but
  # doesn't include the number in the result.
  #
  # Example:
  #   pluralize(2, 'commit')                # 2 commits
  #   pluralize_without_number(2, 'commit') # commits
  #
  # count    - Number to use to determine whether or not to pluralize
  # singular - How the word should look when singular
  #
  # Returns a string.
  def pluralize_without_number(count, singular)
    singular.pluralize(count)
  end

  def explain_viewable_reference(nwo)
    "Only people who can see #{nwo} will see this reference."
  end

  # Helper method for returning instance variable
  # to check if page has been set responsive: true
  def responsive?
    @page_responsive
  end

  # Helper method for returning instance variable
  # to check if page wants to hide the search box
  def hide_search?
    @hide_search
  end

  # Helper method for returning instance variable to check
  # if page should not have responsive padding added to it
  def skip_responsive_padding?
    !!@skip_responsive_padding
  end

  # Helper method for returning instance variable
  # to check if page has been set full_height: true
  def full_height?
    !!@page_full_height
  end

  def sticky_footer?
    !!@page_sticky_footer
  end

  # Helper method for returning instance variable
  # to check if page has been set container_xl: true
  def container_xl?
    @container_xl
  end

  # Helper method for returning instance variable
  # to check if page has been set container_full: true

  def container_full?
    @container_full
  end

  # Helper method for returning instance variable
  # to check if the page has been set skip_pjax_container: true
  def skip_pjax_container?
    !!@skip_pjax_container
  end

  # Helper method for returning instance variable
  # to check if we should force compact header
  def force_compact_header?
    !!@force_compact_header
  end

  # Public: Defines an instance variable that is the global relay id of
  # an object that can be pinned to the user's dashboard.
  #
  # Returns either a global relay id as a String or nil
  def dashboard_pinnable_item_id
    @dashboard_pinnable_item_id
  end

  def body_classes
    [
      ("logged-#{logged_in? ? 'in' : 'out'}"),
      ("enterprise" if enterprise?),
      "env-#{Rails.env.downcase}",
      ("min-width-lg" unless responsive?),
      ("page-responsive" if responsive?),
      ("with-global-sidebar" if logged_in? && current_user.feature_preview_enabled?(:global_nav_experiment) && !marketing_page? && !@hide_header && !auth_sso_page?),
      ("height-full d-flex flex-column" if @page_full_height && !@page_full_height_scrollable),
      ("min-height-full d-flex flex-column" if @page_full_height && @page_full_height_scrollable),
      @page_class,
      ("min-height-full d-flex flex-column" if @page_sticky_footer),
      ("colorblind-themes-v1" if logged_in? && !user_or_global_preview_enabled?(:color_modes_color_blind_themes_2)),
      ("primer-button-break-line" if logged_in? && current_user.feature_flag_enabled_or_raise?(:primer_button_break_line)) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    ].compact
  end

  def html_classes
    [
      ("height-full" if @page_full_height && !@page_full_height_scrollable),
      @html_class
    ].compact
  end

  def last_access_description(key, desc = "token", tooltip_direction = "tooltipped-s")
    cutoff = key.class::ACCESS_CUTOFF_DATE
    if key.accessed_at
      "Last used within the last #{last_accessed_at_time_ago_in_words(key.accessed_at)}"
    else
      if key.created_at && key.created_at > cutoff
        "Never used"
      else
        desc = "No activity has been logged since #{desc} logging began on #{cutoff.strftime('%B %d, %Y')}"
        icon = content_tag("span", class: "tooltipped #{tooltip_direction}", 'aria-label': desc) do
          octicon("info")
        end
        safe_join [icon, " No recent activity"]
      end
    end
  end

  # Public: coarse_time_ago_in_words but doesn't get any more specific than a
  # week. The reason is that the timestamps are only being touched like once a
  # week as of the time of this documentation being written. This is only to be
  # used for last_access_description.
  def last_accessed_at_time_ago_in_words(time)
    diff = Time.now - time
    diff = 0 if diff < 0

    case diff
    when 0..1.week
      "week"
    when 0..1.month
      weeks = number_to_human (diff / 1.week.to_f).ceil
      "#{weeks} weeks"
    when 0..1.year
      months = number_to_human (diff / 1.month.to_f).ceil
      "#{months} months"
    else
      years = number_to_human (diff / 1.year.to_f).ceil
      "#{years} years"
    end
  end

  def coarse_time_ago_in_words(time)
    diff = Time.now - time
    case diff
    when 0..1.day
      "day"
    when 0..1.week
      days = number_to_human (diff / 1.day.to_f).ceil
      "#{days} days"
    when 0..1.month
      weeks = number_to_human (diff / 1.week.to_f).ceil
      "#{weeks} weeks"
    when 0..1.year
      months = number_to_human (diff / 1.month.to_f).ceil
      "#{months} months"
    else
      years = number_to_human (diff / 1.year.to_f).ceil
      "#{years} years"
    end
  end

  def luau_url
    GitHub::WebSocket.luau_url(user_session)
  end

  def luau_worker_src
    web_worker_url("socket-worker.js")
  end

  def service_worker_path
    web_worker_url("service-worker.js")
  end

  def find_file_worker_path
    web_worker_url("find-file-worker.js")
  end

  def find_in_file_worker_path
    web_worker_url("find-in-file-worker.js")
  end

  def current_ui_release_sha
    GitHubUI::Manifest.new.git_sha
  end

  def current_ui_target
    GitHubUI::Manifest.new.ui_manifest_target
  end

  def luau_session_id
    GitHub::WebSocket.luau_session_id(user_session)
  end

  def live_update_view_channel(channel)
    GitHub::WebSocket.signed_channel(channel)
  end

  def invite_or_add_action_word(enterprise_managed: false)
    if GitHub.bypass_org_invites_enabled? || enterprise_managed
      "Add"
    else
      "Invite"
    end
  end

  def enterprise_managed_user?
    return false if GitHub.single_business_environment?
    return false unless logged_in?

    current_user.is_enterprise_managed?
  end

  # Public: GitHub's physical office address for inclusion into
  # email footers, invoices, legal docs, etc.
  #
  # multiline - true or false.
  #
  # Returns address with a line break if multiline:
  # "GitHub, Inc. 88 Colin P Kelly Jr Street<br />San Francisco, CA 94107"
  #
  # Returns a one line string otherwise:
  # "GitHub, Inc. 88 Colin P Kelly Jr Street, San Francisco, CA 94107"
  def github_physical_address(multiline: false)
    if multiline
      safe_join GitHub.physical_address(multiline: true), tag(:br)
    else
      GitHub.physical_address
    end
  end

  def capped_number_with_delimiter(n, limit:)
    str = number_with_delimiter([n, limit].min)
    str += "+" if n > limit
    str
  end

  # Wraps a block with an auto-check tag. Only password checks are currently implemented.
  def auto_check_tag(type, subject: current_user, &block)
    raise "Block required" unless block_given?

    options = if type == :password
      { src: password_check_path }
    else
      raise ArgumentError, "auto_check_tag requires you define attributes for unknown type: #{type}"
    end

    content_tag("auto-check", options) do
      safe_join([capture(&block), csrf_hidden_input_for(password_check_path)])
    end
  end

  def scrubbed_utf8(text)
    return text if text.encoding == ::Encoding::UTF_8 && text.valid_encoding?

    text.dup.force_encoding("UTF-8").scrub!
  end

  # Use me with `<a>` links.
  def test_selector(value, name: nil)
    return if Rails.env.production?
    attribute_name = "data-test-selector"
    attribute_name += "-#{name}" if name
    "#{attribute_name}=#{value}"
  end

  # Deprecated: uses are linted by `Rails/DataHash`.
  # Replace callers with `test_selector` or `test_selector_data_hash`.
  def test_selector_hash(value, name: nil, attribute_name: "test-selector")
    return {} if Rails.env.production?
    attribute_name += "-#{name}" if name
    { "#{attribute_name}" => value }
  end

  # Use me with `<% link_to %>`.
  # A version of `test_selector_hash` that isn't flagged by `Rails/DataHash`.
  def test_selector_data_hash(value, name: nil)
    test_selector_hash(value, name: name, attribute_name: "data-test-selector")
  end

  # Returns a String CSS class name for each issue/pull request state.
  def state_css_class(state, is_draft: false)
    case state.to_s.downcase
    when "merged"
      "State--merged"
    when "open"
      if is_draft
        "State"
      else
        "State--open"
      end
    when "closed"
      "State--closed"
    end
  end

  # Produces an HTML snippet that can be used to ask an end-user to contact
  # support. Designed to work properly in all environments and show the
  # appropriate default copy if a support link isn't configured on an Enterprise
  # installation.
  #
  # On dotcom:
  #   "Please visit <a href=\"https://support.github.com\">https://support.github.com</a>"
  #
  # On Enterprise without a support link configured:
  #   "Please contact your local GitHub Enterprise site administrator"
  #
  # On Enterprise with an email configured:
  #   "Please contact <a href=\"mailto:support@acme.com\">support@acme.com</a>"
  #
  # On Enterprise with a URL configured:
  #   "Please visit <a href=\"https://support.acme.com\">https://support.acme.com</a>"
  #
  # lowercase - Boolean: true to begin the snippet lowercase or false to begin
  #             uppercase. Defaults to false.
  #
  # Returns a String
  def contact_support_snippet(lowercase = false)
    if GitHub.support_link_not_enterprise_default?
      prefix = lowercase ? GitHub.support_link_text_no_link_lowercase : GitHub.support_link_text_no_link
      link = link_to GitHub.support_link, GitHub.support_link_text_mailto_or_link
      safe_join [prefix, " ", link]
    else
      lowercase ? GitHub.support_link_text_lowercase : GitHub.support_link_text
    end
  end

  def show_contact_microsoft_link?(app)
    !GitHub.enterprise? && app.is_a?(OauthApplication) && app.id == GitHub.microsoft_linked_identity_app_id
  end

  def site_favicon(status = nil, extension = "svg")
    url = site_favicon_base_url

    status = case status
    when "error" then "failure"
    when "expected" then "pending"
    when "skipped" then "skipped"
    when "failure", "pending", "success" then status
    else status
    end
    url += "-#{status}" if status

    extension = case extension
    when "svg", "png" then extension
    else "svg"
    end

    "#{url}.#{extension}"
  end

  def site_favicon_base_url
    url = "/favicons/favicon"
    url = GitHub.asset_host_url + url if Rails.env.production?
    url += "-ent" if GitHub.enterprise?
    url += "-dev" if Rails.env.development?

    url
  end

  def avatar_stack_count_class(count)
    if count >= 3
      "AvatarStack--three-plus"
    elsif count == 2
      "AvatarStack--two"
    else
      ""
    end
  end

  def render_seats_more_info(organization)
    return unless GitHub.billing_enabled?

    if organization.delegate_billing_to_business? && organization.business.owner?(current_user)
      render partial: "shared/remaining_seats_more_info", locals: { entity: "enterprise", consumed_licenses_path: enterprise_licensing_path(organization.business) }
    elsif !organization.delegate_billing_to_business?
      render partial: "shared/remaining_seats_more_info", locals: { entity: "organization", consumed_licenses_path: organization_consumed_licenses_path(organization) }
    end
  end

  def seat_or_license(organization)
    if GitHub.enterprise? || organization.delegate_billing_to_business?
      "license"
    else
      "seat"
    end
  end

  def track_render_partial(partial_name, additional_tags = nil, trace: false)
    mysql_count = 0
    mysql_count_start = GitHub::MysqlInstrumenter.query_count
    timer = nil
    partial_tag = "partial:#{partial_name}"

    if trace
      GitHub.tracer.in_span(partial_tag, kind: :internal) do |span|
        timer = Timer.start
        yield
        timer.stop

        mysql_count = GitHub::MysqlInstrumenter.query_count
        span.set_attribute("mysql_queries", mysql_count - mysql_count_start)
      end
    else
      timer = Timer.start
      yield
      timer.stop
    end

    combined_tags = [
      controller_dogstats_tag,
      action_dogstats_tag,
      logged_in_dogstats_tag,
      partial_tag,
      GitHub::Dogstats::DEFAULT_HOST_TAG,
    ]

    combined_tags.concat(additional_tags) if additional_tags

    tags = combined_tags.select { |v| v.start_with?(*REQUEST_RENDER_ALLOWED_TAGS) }
    GitHub.dogstats.distribution("request.render.partial", timer.elapsed_ms, tags: tags)
  end

  # Use these memoized methods to avoid allocating unnecessary strings
  def controller_dogstats_tag
    @_controller_dogstats_tag ||= "controller:#{controller_name}"
  end

  def action_dogstats_tag
    @_action_dogstats_tag ||= "action:#{action_name}"
  end

  def logged_in_dogstats_tag
    @_logged_in_dogstats_tag ||= "logged_in:#{logged_in?}"
  end

  def commit_signature_verification_help_link
    link_to(
      "Learn about vigilant mode",
      "#{GitHub.help_url}/github/authenticating-to-github/displaying-verification-statuses-for-all-of-your-commits",
      class: "Link--inTextBlock"
    )
  end

  def signin_subtitle(ldap = false, emu_first_admin_login = false)
    if ldap
      "Sign in via LDAP"
    elsif emu_first_admin_login
      "Sign in to your new enterprise"
    elsif GitHub.enterprise?
      "Sign in to your account"
    elsif account_switcher_helper.can_add_account?
      "Add an account"
    elsif FeatureFlag.vexi.enabled?(:proxima_first_emu_admin_login_experience, default: false) && GitHub.multi_tenant_enterprise?
      "Sign in as the enterprise admin"
    else
      "Sign in to GitHub"
    end
  end

  def signin_login_field_label(ldap = false)
    login_field_label = ldap ? "Username" : "Username or email address"
  end

  def show_repository_header_placeholder?
    !!@show_repository_header_placeholder
  end

  def utm_memo
    session[:utm_memo] || {}
  end

  def robots_noindex?
    !!@noindex
  end

  def robots_noindex_and_nofollow?
    !!@noindex_and_nofollow
  end

  def seo_canonical_url
    @canonical_url
  end

  def page_richweb
    @page_richweb
  end

  # Determines if the current page is an authentication page or SSO login page
  def auth_sso_page?
    auth_controllers = %w[sessions ldap_identities passwords recoveries two_factor_authentications saml oauth sso]
    auth_controllers.include?(controller_name) ||
      request.path.start_with?("/login", "/logout", "/join", "/password", "/sessions", "/auth", "/sso") ||
      request.path.include?("/saml/") ||
      request.path.include?("/oauth/") ||
      request.fullpath.include?("/sso")
  end

  private

  def set_page_responsive(info)
    info.nil? || info == true
  end

  def default_tagline
    if GitHub.enterprise?
      "Enterprise"
    else
      "Where software is built"
    end
  end

  # Obfuscate a string by converting each char to hex
  def obfuscate_str(str)
    str.each_char.map do |char|
      "&#x#{char.ord.to_s(16)};"
    end.join
  end

  def ensure_local_vars(hash, options)
    vars = (options[:defaults] || {}).merge(hash)
    return vars if Rails.env.production?

    required_vars_not_found = (options[:required] || []) - hash.keys
    if required_vars_not_found.any?
      raise ArgumentError.new("Required local #{"variable".pluralize(required_vars_not_found.size)} #{required_vars_not_found.map { |s| ":#{s}" }.to_sentence} not found.")
    end

    all_possible_arguments = options[:required] | options[:optional] | options[:defaults].keys
    unknown_vars = hash.keys - all_possible_arguments
    if unknown_vars.any?
      raise ArgumentError.new("Unexpected local #{"variable".pluralize(unknown_vars.size)} #{unknown_vars.map { |s| ":#{s}" }.to_sentence } found.")
    end

    vars
  end

  def cursor_pagination_params(action: nil, previous_param: :before, next_param: :after)
    cursor_params = params.dup.permit!.to_hash.with_indifferent_access

    # remove any existing cursor pagination options
    cursor_params.delete(next_param)
    cursor_params.delete(previous_param)

    # overwrites the default controller action
    if action
      cursor_params[:action] = action
    end

    cursor_params
  end

  # Override if business footer should not be enabled in specific contexts.
  def business_footer_enabled?
    true
  end

  def dismiss_content_warning_banner_kv_key
    "dismissed_content_warning_from_flagged_repo.#{current_user.id}.#{current_repository.id}"
  end

  def dismissed_content_warning_banner?
    return false unless logged_in?

    # fallbacks to true if DB cluster is unavailable and does not render the content warning banner
    Repositories::Kv.store.get(dismiss_content_warning_banner_kv_key).value { true }
  end

  # Get the name of the actor to display for the profile link.
  def display_name_for_actor(actor)
    # Use display_login for User and Organizations, but not for Bots or Mannequins.
    # Bots and Mannequins are Users, but we only want to use the display_login value for users and orgs.
    if actor.is_a?(User) && !actor.is_a?(Bot) && !actor.is_a?(Mannequin)
      actor.display_login
    elsif actor.is_a?(Bot) && Apps::Privileged.property(:display_login, app: actor.integration)
      actor.display_login
    else
      actor.to_s
    end
  end
end
