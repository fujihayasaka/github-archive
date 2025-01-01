# typed: false
# frozen_string_literal: true

module Gitkeeper
  autoload :State, "gitkeeper/state"

  # set state, if no conditions are met state would remain nil which is desirable
  # In order to create a conditional that moved quickly at a high level,
  # the `cloning` condition was used twice. Once if the repo is empty, once if it isn't
  # This method is the ideal location for science experiments to pare down the timing
  def gitkeeper_state(repo, check_cache: false)
    return if check_cache && State.good_state?(repo)

    # there are multiple conditions which rely on a repo being locked
    # only hit them if the repo is locked
    state = if repo.locked?
      if repo.moving?
        "move_locked"
      elsif repo.locked_on_disk?
        "locked"
      elsif repo.locked_on_migration?
        "migrating"
      elsif repo.locked_on_billing?
        "billing_locked"
      elsif repo.locked_on_stacks_config?
        "stacks_config"
      end

    elsif is_stacks_config_in_progress?(repo)
      "stacks_config"

    # there are multiple conditions that are hit only if a repo is empty
    # only hit them if the repo is empty
    elsif repo.empty?
      if !current_user_can_push?
        "nothing"
      elsif specified_online(repo)
        # a repository can be empty and cloning simultaneously
        if repo.cloning_from_template?
          "cloning"
        else
          potential_state = (GitHub.porter_available? && repo.is_importing?) ? "importing" : "empty"
          if potential_state == "empty" && viewing_graphs?
            "blank_slate"
          elsif working_with_new_blob?
            check_cache = false # prevent caching this state
            nil # Act like repo is in a good state since user is trying to create first blob
          else
            potential_state
          end
        end
      else
        !repo.pushed_at.blank? ? "down" : "offline"
      end

    # catch other potential states
    else
      if is_creating?(repo)
        if repo.parent_id?
          "forking"
        elsif repo.mirror
          "mirroring"
        end
      # a repository can be !empty and cloning simultaneously
      elsif specified_online(repo) && repo.cloning_from_template?
        "cloning"
      elsif with_database_error_fallback(fallback: false) { repo.heads.empty? }
        "nobranch"
      elsif !current_commit && with_database_error_fallback(fallback: false) { bad_default_branch_ref? } && !repair_bad_default_branch_ref
        "content_nonexist"
      end
    end

    if check_cache
      State.set_cache_key(repo) unless state
    end
    state
  end

  def is_stacks_config_in_progress?(repo)
    false
  end

  def is_creating?(repo)
    repo.created_at.after?(1.day.ago) && with_database_error_fallback(fallback: false) { repo.creating? }
  end

  def working_with_new_blob?
    params[:controller] == "blob" && %w(new create preview add_push_protection_bypass).include?(params[:action])
  end

  def viewing_graphs?
    params[:controller] == "graphs"
  end

  def specified_online(repo)
    repository_specified? && !repo.offline?
  end
end
