# typed: true
# frozen_string_literal: true

module Gists
  # Controls the gist public listing views
  # eg https://gist.github.com/discover
  class ListingPageView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include TextHelper

    attr_reader :gists, :atom_feed_path, :pagination_info, :type,
                :sort_direction

    def page_title
      "Discover gists"
    end

    def page_meta_description
      I18n.t("gists.meta_description")
    end

    def has_gists?
      gists.length > 0
    end

    def next_label
      if sort_direction == "asc"
        "Newer"
      else
        "Older"
      end
    end

    def previous_label
      if sort_direction == "asc"
        "Older"
      else
        "Newer"
      end
    end

    def search_sort_fields
      %w(created updated)
    end

    def search_sort_labels
      {
        %w(created desc)  => "Recently created",
        %w(created asc)   => "Least recently created",
        %w(updated desc)  => "Recently updated",
        %w(updated asc)   => "Least recently updated",
      }
    end

    def search_sort_directions
      %w(desc asc)
    end

    def sorting_enabled?
      has_gists? && pagination_info.sorting_enabled?
    end

    def type_label
      if !GitHub.public_repositories_available? && @type == :public
        "internal"
      else
        @type.to_s
      end
    end
  end
end
