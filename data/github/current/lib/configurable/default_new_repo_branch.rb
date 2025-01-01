# typed: false
# frozen_string_literal: true

module Configurable
  module DefaultNewRepoBranch
    KEY = "default_new_repo_branch"

    # Public: Set this user's/org's/business's default branch name for new repositories.
    #
    # name - the branch name to use as the default branch for new repositories
    # actor - the User who is changing this setting
    # enforce - a Boolean indicating whether the setting is enforced on organizations
    #           within the enterprise; only applicable when called on a Business
    #
    # Returns a Boolean indicating success. Will return false when the given branch
    # name is not a valid branch name.
    def set_default_new_repo_branch(name, actor:, enforce: false)
      normalized_name = Git::Ref.normalize(name)
      return false unless normalized_name && name == normalized_name

      previous_value = config.get(KEY)

      changed = if enforce
        config.set!(KEY, normalized_name, actor)
      else
        config.set(KEY, normalized_name, actor)
      end
      return false unless changed

      hydro_data = {
        actor: actor,
        old_default_branch: previous_value,
        new_default_branch: normalized_name,
        enforced: enforce,
      }
      if is_a?(Business)
        hydro_data[:business] = self
      else
        hydro_data[:repository_owner] = self
      end

      # Hydro
      GlobalInstrumenter.instrument("user.change_new_repository_default_branch_setting",
        hydro_data)

      # Audit log
      instrument :update_new_repository_default_branch_setting,
        old_default_branch: previous_value,
        new_default_branch: normalized_name,
        actor: actor

      true
    end

    # Public: Remove this user's/org's/business's customized default branch name, so
    # that new repositories they make going forward will have the GitHub-recommended
    # default branch.
    #
    # actor - the User making this change
    #
    # Returns nothing.
    def clear_default_new_repo_branch(actor:)
      previous_value = config.get(KEY)

      config.delete(KEY, actor)

      hydro_data = { actor: actor, old_default_branch: previous_value }
      if is_a?(Business)
        hydro_data[:business] = self
      else
        hydro_data[:repository_owner] = self
      end

      # Hydro
      GlobalInstrumenter.instrument("user.change_new_repository_default_branch_setting", hydro_data)

      # Audit log
      instrument :clear_new_repository_default_branch_setting,
        old_default_branch: previous_value,
        actor: actor
    end

    def recommended_name
      "main"
    end
    module_function :recommended_name

    # Public: Get the name that should be used for the default branch in
    # any repositories this user/org/business makes.
    def default_new_repo_branch
      custom_default_new_repo_branch || recommended_name
    end

    # Public: Get the name that the user/org/business has set explicitly as
    # their preference for new repositories, if any.
    def custom_default_new_repo_branch
      config.get(KEY).presence
    end

    # Public: Is the custom default branch setting enforced for organizations
    # in the enterprise, and users in a single-business environment?
    #
    # Returns a Boolean.
    def custom_default_new_repo_branch_enforced?
      !!config.final?(KEY)
    end

    # Public: Has this user/org/business set a custom default new repo branch name?
    #
    # Returns a Boolean.
    def custom_default_new_repo_branch_name?
      !custom_default_new_repo_branch.nil?
    end
  end
end
