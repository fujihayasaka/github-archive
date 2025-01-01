# typed: true
# frozen_string_literal: true

module Search
  class DotcomRepoResultView < RepoResultView

    attr_reader :forks_count, :license, :pushed_at, :private, :repo_link, :followers_link, :mirror, :archived

    alias :private? :private
    alias :pushed :pushed_at

    # Create a new RepoResultView from a `repository` document hash returned from
    # the dotcom search API.
    #
    # hash - Document Hash returned by dotcom search API.
    #
    def initialize(dotcom_hash)

      @id          = dotcom_hash["id"]
      @name        = dotcom_hash["name"]
      @description = dotcom_hash["description"]
      @size        = dotcom_hash["size"].to_i
      @forks       = dotcom_hash["forks_count"].to_i
      @language    = dotcom_hash["language"]
      @fork        = dotcom_hash["fork"]
      @private     = dotcom_hash["private"]
      @mirror      = dotcom_hash["mirror_url"]
      @archived    = dotcom_hash["archived"]
      @owner       = dotcom_hash["owner"]
      @topics      = dotcom_hash["topics"]
      @repo_link   = dotcom_hash["html_url"]
      @license     = dotcom_hash["license"]
      @pushed_at   = Time.parse(dotcom_hash["pushed_at"]) if dotcom_hash["pushed_at"]
      @highlights  = Search::DotcomHighlights.highlights(dotcom_hash["text_matches"])

      @followers        = dotcom_hash["stargazers_count"]
      @followers_link   = dotcom_hash["followers_url"]
    end

    def public?
      !private
    end

    def visibility
      private? ? "private" : "public"
    end

    # Public: Returns true if we should show the license this repository uses.
    def show_license?
      license && license["key"].downcase != "other"
    end

    # Public: Returns the name of the License on this Repository or nil.
    def license_name
      license && license["spdx_id"]
    end

    # Public: Returns true if the repository is owned by an organization.
    def owned_by_organization?
      @owner && @owner["type"] == "Organization"
    end

    # Returns the `login` name of the owner of the current repository.
    def owner
      @owner["login"] if @owner
    end

    def css
      [@private ? "private" : "public", @fork ? "fork" : "source"].join(" ")
    end

    def flipper_id
      nil
    end
  end  # RepoResultView
end  # Search
