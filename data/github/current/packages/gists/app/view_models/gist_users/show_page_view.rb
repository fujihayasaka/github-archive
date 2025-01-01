# typed: true
# frozen_string_literal: true

module GistUsers
  # Controls the gist user index view
  # eg https://gist.github.com/defunkt
  class ShowPageView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include TextHelper

    extend T::Sig

    attr_reader :user, :gists, :sidebar_counts, :atom_feed_path, :current_page,
                :has_filterable_gists, :sort_direction, :viewer

    sig { returns(String) }
    def page_title
      "#{user}’s gists"
    end

    def page_meta_description
      I18n.t("gist_profiles.meta_description", user: user)
    end

    sig { returns(T::Boolean) }
    def your_profile?
      viewer == user
    end

    sig { returns(T::Boolean) }
    def show_spammy_alert?
      user.spammy? && viewer&.site_admin?
    end

    sig { returns(T::Boolean) }
    def has_gists?
      gists.size > 0
    end

    # Public: Yield each Gist and the first associated Blob
    #         Blob can be nil in cases of corrupt/unreadable gists
    def gists_with_first_blob
      Enumerator.new do |yielder|
        gists.each do |gist|
          blob = gist.files.detect { |b| b.present? }
          yielder.yield gist, blob
        end
      end
    end

    sig { returns(String) }
    def next_label
      if sort_direction == "asc"
        "Newer"
      else
        "Older"
      end
    end

    sig { returns(String) }
    def previous_label
      if sort_direction == "asc"
        "Older"
      else
        "Newer"
      end
    end

    sig { returns([String, String]) }
    def search_sort_fields
      %w{created updated}
    end

    sig { returns(T::Hash[[String, String], String]) }
    def search_sort_labels
      {
        %w{created desc}  => "Recently created",
        %w{created asc}   => "Least recently created",
        %w{updated desc}  => "Recently updated",
        %w{updated asc}   => "Least recently updated",
      }
    end

    sig { returns(T::Array[String]) }
    def search_sort_directions
      %w{desc asc}
    end

    sig { returns(String) }
    def profile_name
      user ? user.safe_profile_name : "Anonymous"
    end

    sig { returns(String) }
    def login
      user ? user.display_login : "anonymous"
    end

    sig { returns(Integer) }
    def forked_count
      sidebar_counts[:forked]
    end

    sig { returns(T::Boolean) }
    def show_forked_tab?
      current_page == :forked || forked_count > 0
    end

    sig { returns(Integer) }
    def starred_count
      sidebar_counts[:starred]
    end

    sig { returns(T::Boolean) }
    def show_starred_tab?
      current_page == :starred || sidebar_counts[:starred] > 0
    end

    sig { returns(Integer) }
    def all_count
      sidebar_counts[:all]
    end

    sig { returns(T::Boolean) }
    def all_gists?
      current_page == :all
    end

    # Show the visibility filters only if we're on our own profile, and there are gists
    sig { returns(T::Boolean) }
    def show_filters?
      your_profile? && has_filterable_gists
    end

    sig { returns(T.nilable(String)) }
    def visibility_prefix_path
      case current_page
      when :all
        urls.user_gists_path(user)
      when :forked
        urls.user_forked_gists_path(user)
      when :starred
        urls.user_starred_gists_path(user)
      end
    end

    sig { params(shortened: T::Boolean).returns(T.nilable(String)) }
    def scope_name(shortened: true)
      case current_page
      when :all
        return "gists" if shortened && your_profile?
        "public gists"
      when :forked
        "forked gists"
      when :starred
        "starred gists"
      end
    end

    sig { params(visibility: T.nilable(String)).returns(String) }
    def visibility_name(visibility)
      case visibility
      when "public"
        "Public"
      when "secret"
        "Secret"
      else
        "All"
      end
    end

    sig { returns(String) }
    def public_visibility_path
      "#{visibility_prefix_path}/public"
    end

    sig { returns(String) }
    def secret_visibility_path
      "#{visibility_prefix_path}/secret"
    end
  end
end
