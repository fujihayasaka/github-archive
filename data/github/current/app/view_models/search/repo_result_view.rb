# typed: true
# frozen_string_literal: true

module Search
  class RepoResultView
    include EscapeHelper
    include TextHelper

    attr_reader :id, :name, :description, :size, :forks, :followers, :template,
                :language, :pushed, :fork, :public, :repo, :mirror, :archived,
                :help_wanted_issues_count, :good_first_issue_issues_count, :sponsorable, :has_funding_file

    attr_accessor :sponsored
    alias :public? :public
    alias :pushed_at :pushed
    alias :mirror? :mirror
    alias :archived? :archived
    alias :template? :template
    alias :sponsorable? :sponsorable
    alias :has_funding_file? :has_funding_file

    delegate :owner_id, to: :repo

    # Create a new RepoResultView from a `repository` document hash returned from
    # the Elasticsearch index.
    #
    # hash - Document Hash returned by Elasticsearch
    #
    def initialize(hash)
      source = hash["_source"]

      @id          = hash["_id"]
      @repo        = hash["_model"]
      @name        = source["name"]
      @description = source["description"]
      @size        = source["size"].to_i
      @forks       = source["forks"].to_i
      @followers   = source["followers"].to_i
      @language    = Search.language_name_from_id(source["language_id"])
      @fork        = source["fork"]
      @public      = source["public"]
      @pushed      = Time.parse(source["pushed_at"])
      @mirror      = source["mirror"]
      @template    = source["template"]
      @archived    = source["archived"]
      @highlights  = hash["highlight"]
      @license_id  = source["license_id"]
      @sponsorable = source["sponsorable"]
      @has_funding_file = source["has_funding_file"]
      @help_wanted_issues_count = source["help_wanted_issues_count"].to_i
      @good_first_issue_issues_count = source["good_first_issue_issues_count"].to_i

      @topics = if source["ranked_hashtags"]
        source["ranked_hashtags"].map { |h| h["applied"] }.compact
      end
      @suggested_topics = if source["ranked_hashtags"]
        source["ranked_hashtags"].map { |h| h["suggested"] }.compact
      end
    end

    def good_first_issue_label
      repo.good_first_issue_label
    end

    def help_wanted_label
      repo.help_wanted_label
    end

    def private?
      !public?
    end

    def visibility
      repo.visibility
    end

    def type
      RepositoriesTypeHelper.type(visibility: visibility, mirror: mirror?, archived: archived?,
                                  template: template?)
    end

    # Returns the parent Repository or nil
    def parent
      repo.parent
    end

    # Public: Returns true if we should show the license this repository uses.
    def show_license?
      license && !license.other?
    end

    # Public: Should 'X issues need help' link be shown for the repository.
    #
    # Returns a Boolean.
    def show_issues_needing_help_link?
      repo.has_issues?
    end

    # Public: Returns the name of the License on this Repository or nil.
    def license_name
      license.try(:spdx_id)
    end

    # Returns true if there are highlight fragments for this repository. The
    # highlight fragments contain text from the various repository fields with the
    # relevant search terms surrounded by <em> tags.
    def highlights?
      !@highlights.nil?
    end

    # Return the repo description. The description may or may not contain
    # highlight tags, but either way it has been HTML escaped and is html_safe.
    #
    # Returns an HTML escaped description String.
    def hl_description
      return @hl_description if defined? @hl_description
      @hl_description =
          if highlights? && @highlights.key?("description")
            GitHub::Goomba::HighlightedSearchResultPipeline.to_html(find_hl_text(@description, @highlights["description"].first))
          else
            formatted = GitHub::Goomba::DescriptionPipeline.to_html(@description.to_s)
            HTMLTruncator.new(formatted, 350).to_html(wrap: false)
          end
    end

    # Returns the repo description with emoji but without any links. Good for use
    # nesting the description inside of a link tag, like on mobile.
    #
    # Returns an HTML escaped description String.
    def linkless_description
      formatted = GitHub::Goomba::SimpleDescriptionPipeline.to_html(@description.to_s)
      HTMLTruncator.new(formatted, 350).to_html(wrap: false)
    end

    # Public: Returns true if the repository is owned by an organization.
    def owned_by_organization?
      @repo.owner && @repo.owner.organization?
    end

    # Returns the `login` name of the owner of the current repository.
    def owner
      @repo.owner.display_login if @repo.owner
    end

    # Returns true if the repository is a fork with a valid parent repo.
    def forked?
      fork && parent.present?
    end

    def name_with_owner_without_highlighting
      "#{owner}/#{name}"
    end

    # Returns the name_with_owner String for the repository. It may or may not
    # contain highlight tags, but either way it has been HTML escaped and is
    # html_safe.
    #
    # Returns an HTML escaped name_with_owner String.
    def name_with_owner
      if highlights? && @highlights.key?("name_with_owner")
        return @highlights["name_with_owner"].first
      end

      hl_name =
          if highlights?
            if @highlights.key?("name")
              @highlights["name"].first
            elsif @highlights.key?("name.camel")
              @highlights["name.camel"].first
            elsif @highlights.key?("name.ngram")
              @highlights["name.ngram"].first
            end
          end
      hl_name = ERB::Util.force_escape(@name) if hl_name.nil?
      safe_join([owner, hl_name], "/")
    end

    # Returns the list of suggested topics for this repository.
    #
    # Returns an Array of Strings, empty if none exist.
    def suggested_topics
      @suggested_topics.present? ? @suggested_topics : []
    end

    # Returns the list of topics that have been applied to this repository.
    #
    # Returns an Array of Strings, empty if none exist.
    def topics
      @topics.present? ? @topics : []
    end

    def platform_type_name
      "Repository"
    end

    def populate_results_data(starred_by_current_user)
      language = Linguist::Language.find_by_name(@language) if @language

      @color = language.color if language

      @type = type

      @owned_by_organization = owned_by_organization?

      @hl_trunc_description = truncate_html(hl_description, 140) if @description

      @hl_name = name_with_owner

      @starred_by_current_user = starred_by_current_user
    end

    def for_frontend_rendering
      {
        id: @id,
        archived: @archived,
        color: @color,
        followers: @followers,
        has_funding_file: @has_funding_file,
        hl_name: @hl_name,
        hl_trunc_description: @hl_trunc_description,
        language: @language,
        mirror: @mirror,
        owned_by_organization: @owned_by_organization,
        public: @public,
        repo: ::Search::ResultsView::repository_for_frontend_rendering(@repo.repository),
        sponsorable: @sponsorable,
        topics: @topics,
        type: @type,
        help_wanted_issues_count: @help_wanted_issues_count,
        good_first_issue_issues_count: @good_first_issue_issues_count,
        starred_by_current_user: @starred_by_current_user
      }
    end

    # Returns true if view should show the sponsor button.
    def show_sponsor_button?
      return false unless has_funding_file?
      return false unless GitHub.sponsors_enabled?
      repo.show_sponsor_button?
    end

    private

    # Private: Returns a License or nil.
    def license
      return @license if defined? @license

      @license = if @license_id
        License.find_by_id(@license_id.to_i)
      end
    end

    # Given some normal text and a highlighted fragment from that text, return
    # the fragment with leading and/or trailing ellipsis to indicate its
    # position in the original text. If the highlighted fragment is not
    # found in the original text then return nil.
    #
    # text      - The original text String.
    # highlight - The highlighted fragment String.
    #
    # Returns a highlighted text fragment.
    def find_hl_text(text, highlight)
      clean_text = ERB::Util.force_escape(text.gsub(/<\/?em>/, ""))
      clean_hl = ERB::Util.force_escape(highlight.gsub(/<\/?em>/, ""))

      return highlight if clean_hl == clean_text

      pos = clean_text.index(clean_hl)
      # If pos is nil, we couldn't find the highlight in the text. This probably
      # means there was an escaped character in the text. Just return the
      # highlight without ellipses.
      return highlight unless pos

      # beginning of string
      if 0 == pos
        safe_join([highlight, "..."], " ")

      # end of string
      elsif clean_hl.length + pos == clean_text.length
        safe_join(["...", highlight], " ")

      # middle of string
      else
        safe_join(["...", highlight, "..."], " ")
      end
    end
  end  # RepoResultView
end  # Search
