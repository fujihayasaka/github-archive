# typed: false
# frozen_string_literal: true

module SearchHelper
  # Public: Given a search string, append a space if the string isn't blank, which
  # is helpful so a user can just start typing additional query modifiers as
  # soon as they focus the field.
  #
  # query - String
  #
  # Returns a String.
  def search_input_value_for(query)
    query.blank? ? "" : "#{query.rstrip} "
  end

  # Generates a link tag that emits a `search_result.click` event when clicked.
  # This event logs a user clicking through a specific search result.
  def link_to_with_hydro_search_tracking(text, url, click_data, options = {})
    link_to text, url, options.merge(data: hydro_search_click_tracking_data(click_data))
  end

  # Formats hydro data for a `search_result.click` event
  def hydro_search_click_tracking_data(click_data)
    hydro_click_tracking_attributes("search_result.click", search_result_data(click_data))
  end

  # Formats the given click data
  def search_result_data(click_data)
    hit_object = click_data[:hit_object]
    return unless hit_object.present?

    {
      page_number: click_data[:page_number],
      per_page: click_data[:per_page],
      query: click_data[:query] || params[:q],
      result_position: click_data[:result_position],
      click_id: hit_object.id,
      result: {
        id: hit_object.id,
        global_relay_id: hit_object.try(:global_relay_id),
        model_name: hit_object.class.name,
        url: click_data[:hit_url],
      },
    }
  end

  def license_options_for_select
    licenses = License.all(hidden: true).reject(&:pseudo_license?).
      sort_by { |license| [license.key, license.name] }
    licenses = licenses.map { |license| [license.name, license.key] }
    options_for_select(licenses)
  end

  def license_family_options_for_select
    licenses = License::LICENSE_FAMILY_NAMES.sort_by { |key, name| [key, name] }.
      map { |(key, name)| [name, key] }
    options_for_select(licenses)
  end

  def related_topic_url(topic_name, query:)
    if GitHub.enterprise?
      search_path(q: "topic:#{topic_name} #{query}".strip, type: "Repositories")
    else
      "/topics/#{topic_name}"
    end
  end

  def search_result_topic_url(topic_name, forked:, org:)
    if GitHub.enterprise?
      qualifiers = ["topic:#{topic_name}"]
      qualifiers << "fork:true" if forked
      qualifiers << "org:#{org}" if org
      search_path(q: qualifiers.join(" "), type: "Repositories")
    else
      "/topics/#{topic_name}"
    end
  end

  def search_result_package_topic_url(topic_name)
    link_to_search \
      q: "topic:#{topic_name}",
      type: "RegistryPackages",
      s: params[:s],
      o: params[:o],
      package_type: params[:package_type]
  end

  def link_to_sorted_search(sort_option)
    (field, dir) = sort_option
    link_to_search(
      s: field,
      o: dir,
      p: nil,
      q: params[:q],
      type: params[:type],
      l: params[:l],
    )
  end

  def search_sort_menu_item(sort_option, current_sort, enable_pjax: true)
    item_params = {
      class: "select-menu-item",
      role: "menuitemradio",
      "aria-checked": sort_option == current_sort,
      href: link_to_sorted_search(sort_option),
    }

    if enable_pjax
      item_params["data-pjax"] = true
    end
    content_tag(:a, item_params) do
      yield
    end
  end

  def link_to_search(options)
    options = { q: params[:q], type: params[:type], s: params[:s], l: params[:l], o: params[:o] }.merge(options)
    if current_repository
      repo_search_path(options.merge(repository: current_repository,
                                     user_id: current_repository.user))
    elsif params[:topic_name]
      topic_show_path(params[:topic_name], options)
    else
      search_path(options)
    end
  end

  def link_to_dotcom_search(options)
    dotcom_search_path(options)
  end

  def search_sort_directions
    %w[desc asc]
  end

  def repo_search_sort_fields
    ["", "stars", "forks", "updated"]
  end

  def repo_search_sort_labels
    {
      ["", "desc"] => "Best match",
      %w[stars desc]  => "Most stars",
      %w[stars asc]   => "Fewest stars",
      %w[forks desc]  => "Most forks",
      %w[forks asc]   => "Fewest forks",
      %w[updated desc]  => "Recently updated",
      %w[updated asc]   => "Least recently updated",
    }
  end

  def code_search_sort_fields
    ["", "indexed"]
  end

  def code_search_sort_labels
    {
      ["", "desc"] => "Best match",
      %w[indexed desc]  => "Recently indexed",
      %w[indexed asc]   => "Least recently indexed",
    }
  end

  def commit_search_sort_fields
    ["", "committer-date", "author-date"]
  end

  def commit_search_sort_labels
    {
      ["", "desc"] => "Best match",
      %w[author-date desc] => "Recently authored",
      %w[author-date asc] => "Least recently authored",
      %w[committer-date desc] => "Recently committed",
      %w[committer-date asc] => "Least recently committed",
    }
  end

  def issues_search_sort_fields
    ["", "comments", "created", "updated"]
  end

  def discussions_search_sort_fields
    ["", "score", "comments", "created", "updated"]
  end

  def issues_search_sort_labels
    {
      ["", "desc"] => "Best match",
      %w[comments desc] => "Most commented",
      %w[comments asc]  => "Least commented",
      %w[created desc] => "Newest",
      %w[created asc]  => "Oldest",
      %w[updated desc]  => "Recently updated",
      %w[updated asc]   => "Least recently updated",
    }
  end

  def discussions_search_sort_labels
    {
      ["", "desc"] => "Best match",
      %w[comments desc] => "Most commented",
      %w[comments asc] => "Least commented",
      %w[created desc] => "Newest",
      %w[created asc] => "Oldest",
      %w[updated desc] => "Recently updated",
      %w[updated asc] => "Least recently updated",
    }
  end

  def packages_search_sort_fields
    ["", "downloads", "created", "updated"]
  end

  def packages_search_sort_labels
    {
      ["", "desc"] => "Best match",
      %w[downloads desc] => "Most downloads",
      %w[downloads asc] => "Fewest downloads",
      %w[created desc] => "Newest",
      %w[created asc]  => "Oldest",
      %w[updated desc]  => "Recently updated",
      %w[updated asc]   => "Least recently updated",
    }
  end

  def user_search_sort_fields
    ["", "followers", "joined", "repositories"]
  end

  def user_search_sort_labels
    {
      ["", "desc"] => "Best match",
      %w[followers desc] => "Most followers",
      %w[followers asc]  => "Fewest followers",
      %w[joined desc] => "Most recently joined",
      %w[joined asc]  => "Least recently joined",
      %w[repositories desc]  => "Most repositories",
      %w[repositories asc]   => "Fewest repositories",
    }
  end

  def wiki_search_sort_fields
    ["", "updated"]
  end

  def wiki_search_sort_labels
    {
      ["", "desc"]     => "Best match",
      %w[updated desc] => "Recently updated",
      %w[updated asc]  => "Least recently updated",
    }
  end

  def global_search_hotkey
    parsed_useragent.name == "Firefox" ? nil : "/"
  end

  def local_search_hotkey
    parsed_useragent.name == "Firefox" ? nil : "Control+/,Meta+/"
  end
end
