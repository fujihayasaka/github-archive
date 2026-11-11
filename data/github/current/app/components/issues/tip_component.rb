# typed: true
# frozen_string_literal: true

module Issues
  class TipComponent < ApplicationComponent
    include ActionView::Helpers::UrlHelper
    include IssuesHelper
    include TipsHelper
    include ResilienceHelper

    attr_reader :repo, :parsed_issues_query, :pulls_only, :selected_tip, :tips

    def initialize(repo:, tips: nil, pulls_only: false, parsed_issues_query: nil)
      @repo = repo
      @pulls_only = pulls_only
      @parsed_issues_query = parsed_issues_query
      @tips = tips
    end

    def before_render

      # most tips need helpers, so we initialize them in before_render
      # but we also now allow the object to be created with tips
      # in which case we don't initialize any additional ones

      if !@tips
        @tips = [
          "Adding no:label will show everything without a label.",
          "no:milestone will show everything without a milestone.",
          "Add no:assignee to see everything that’s not assigned.",
          "Follow long discussions with comments:>50.",
          "Updated in the last three days: updated:>#{(Date.today - 3.days).to_formatted_s(:db)}.",
          "What’s not been updated in a month: updated:<#{(Date.today - 1.month).to_formatted_s(:db)}.",
          "Mix and match filters to narrow down what you’re looking for.",
          'Exclude everything labeled <code class="bg-gray-2 bg-gray-3 p-1 rounded">bug</code> with -label:bug.',
          "Type <kbd>g</kbd> <kbd>i</kbd> on any issue or pull request to go back to the issue listing page.",
          "Type <kbd>g</kbd> <kbd>p</kbd> on any issue or pull request to go back to the pull request listing page.",
        ]

        if @pulls_only && repo
          tip = with_database_error_fallback(fallback: nil) do
            "Filter pull requests by the default branch with base:#{repo.default_branch}."
          end
          @tips << tip unless tip.nil?
        end

        # linked: qualifier tips
        if @pulls_only
          @tips << "Find all pull requests that aren't related to any open issues with -linked:issue."
        else
          @tips << "Find all open issues with in progress development work with linked:pr."
        end

        # Triage mode.
        if repo && repo.pushable_by?(current_user)
          @tips << "Click a checkbox on the left to edit multiple issues at once."
        end

        # User-centric tips.
        if logged_in?
          @tips << "Exclude your own issues with -author:#{current_user.display_login}."
          @tips << "Notify someone on an issue with a mention, like: @#{current_user.display_login}."
          @tips << "Find everything you created by searching author:#{current_user.display_login}."
          @tips << "Ears burning? Get @#{current_user.display_login} mentions with mentions:#{current_user.display_login}."
        end

        # Grab a random team for a few sample filters.
        if logged_in? && repo.try(:in_organization?)
          team = repo.organization.teams_for(current_user).sample
          @tips << "Check team mentions with team:#{team.combined_slug}." if team
        end
      end
      @selected_tip = select_tip
    end

    # Grab a random rendered tip.
    #
    # Returns a String.
    def select_tip
      render_link(tips.sample, components: parsed_issues_query) do |components|
        if repo
          issues_path(
            user_id: repo.owner,
            repository: repo,
            q: Search::Queries::IssueQuery.stringify(components))
        else
          all_issues_path(q: Search::Queries::IssueQuery.stringify(components))
        end
      end
    end
  end
end
