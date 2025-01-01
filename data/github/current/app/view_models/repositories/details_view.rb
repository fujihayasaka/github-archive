# typed: false
# frozen_string_literal: true

module Repositories
  class DetailsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include EnterpriseManagedUsersHelper
    include ResilienceHelper
    attr_reader :repository, :repository_is_offline, :cap_view_filter, :viewer_can_read_repo

    def forking_allowed?
      forkability_error.nil?
    end

    # Note: this method is not exhaustive. If it returns true, there is definitely nowhere to fork.
    #   If it returns false, it means it couldn't definitively rule out the ability to fork.
    #   This heavier calculation is done on and handled via the fork partial.
    def nowhere_to_fork?
      current_user == repository.owner && current_user&.organizations&.empty?
    end

    def forkability_error_message
      return if forking_allowed?
      "Cannot fork because #{forkability_error}."
    end

    def include_sponsor_button_fragment?
      return false unless GitHub.sponsors_enabled?
      return false if repository_is_offline
      return false unless viewer_can_read_repo
      !current_user&.has_any_trade_restrictions? && repository.show_sponsor_button?
    end

    # Returns a hash of local variables that govern the behaviour of the "Watch" button on
    # repository pages.
    #
    # Returns Hash<Symbol,Object> with the following keys:
    #   repository_id      - Integer Repository ID.
    #   subscription_type  - Symbol describing the user's subscription status relative to this
    #                        repository. One of (:watching, :releases_only, :ignoring, :none).
    #   show_watcher_count - Boolean determining whether or not to show a count of the number of
    #                        watchers for the repository.
    #   classes            - String containing CSS classes to apply to the top level <details>
    #                        element of menu.
    def subscription_menu_options(subscription_status)
      subscription_type = if !subscription_status&.success?
        nil
      elsif subscription_status.subscribed?
        :watching
      elsif subscription_status.thread_type_only?(Release)
        :releases_only
      elsif subscription_status.participation_only?
        :none
      elsif subscription_status.ignored?
        :ignoring
      end

      {
        repository: {
          id: repository.id,
          name: repository.name,
          owner: repository.owner.display_login,
          public: repository.public,
        },
        subscription_type: subscription_type,
        show_watcher_count: true,
        inside_flash_alert: false
      }
    end

    private

    def forkability_error
      return @forkability_error if defined?(@forkability_error)

      @forkability_error = with_database_error_fallback(fallback: "forking is currently unavailable") do
        begin
          if repository.forking_disabled?
            "forking is disabled"
          elsif repository.locked?
            "repository is locked"
          elsif repository.disabled?(viewer: current_user)
            "repository is disabled"
          elsif repository.access.dmca?
            "repository is unavailable due to DMCA takedown"
          elsif repository_is_offline
            "repository is offline"
          elsif nowhere_to_fork?
            "you own this repository and are not a member of any organizations"
          elsif repository.probably_empty?
            "repository is empty"
          elsif emu_contribution_blocked?(repository)
            "the repository is outside of your enterprise #{enterprise_name}"
          end
        rescue GitRPC::ConnectionError => e
          Failbot.report! e
          "repository is offline"
        end
      end
    end
  end
end
