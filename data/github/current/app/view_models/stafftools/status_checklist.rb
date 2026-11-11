# typed: true
# rubocop:disable Primer/PrimerOcticon
# frozen_string_literal: true

module Stafftools
  module StatusChecklist
    include ActionView::Helpers::TagHelper
    include OcticonsHelper

    # HTML li tag for a status checklist. Should be used within a ul with the
    # class "status-check-list".
    #
    # status - the status of the item. Possible values:
    #           :error or :failed - produces a red alert octicon
    #           :neutral or falsey - produces a grey X octicon
    #           anything else produces a green check mark octicon
    # text - The text body of the li tag.
    # note - A tooltip for the list item. Defaults to nil.
    #
    # Returns a string containing an html list item.
    def status_li(status, text, note = nil)

      text = content_tag :abbr, text, title: note unless note.nil? # rubocop:disable Rails/ViewModelHTML

      if status == :error || status == :failed
        li_class = "failed"
        icon_class = "alert"
      elsif status == :neutral || !status
        li_class = "neutral"
        icon_class = "x"
      else
        li_class = ""
        icon_class = "check"
      end

      icon = octicon(icon_class)
      text = safe_join([icon, text], " ")
      li = content_tag :li, text, class: li_class # rubocop:disable Rails/ViewModelHTML
    end

    # What is the db state for this git repo?
    #
    # git_repo - Repository or Gist
    def git_repo_db_state(git_repo)
      if git_repo.active?
        status_li(:ok, "Database record: ok")
      else
        status_li(:neutral, "Database record: inactive")
      end
    end

    # What is the git state for this git repo?
    #
    # git_repo - Repository or Gist
    def git_repo_git_state(git_repo)
      state = :ok
      msg = "ok"

      if !git_repo.exists_on_disk?
        state = :failed
        msg = "not on disk"
      elsif git_repo.offline?
        state = :failed
        msg = "offline"
      elsif git_repo.access.broken?
        state = :failed
        msg = "flagged as broken"
      elsif git_repo.empty?
        state = :neutral

        if git_repo.fork?
          msg = "fork in progress"
        elsif git_repo.try(:mirror)
          msg = "mirror in progress"
        else
          msg = "empty"
        end
      end

      status_li(state, "Git repository: #{msg}")
    end

    def git_backup_state(git_repo)
      return unless GitHub.realtime_backups_enabled?
      state = git_repo.backup_state
      case state
      when :available
        state = :ok
        msg = "ok"
      when :unavailable
        state = :neutral
        msg = "unavailable"
      when :disabled
        state = :neutral
        msg = "disabled"
      else
        state = :neutral
        msg = "unknown: #{state}"
      end

      status_li(state, "Backup: #{msg}")
    end

    # What is the fs state for this git repo?
    #
    # git_repo - Repository or Gist
    def git_repo_fs_state(git_repo)
      begin
        if GitHub::Spokes.client.available?(git_repo)
          state = :online
          msg = "online"
        else
          state = :failed
          msg = "offline"
        end
      rescue GitHub::Spokes::ClientError, Faraday::Error => boom
        state = :failed
        msg = "rpc failure: #{boom}"
      end

      status_li(state, "Fileserver: #{msg}")
    end

  end
end
