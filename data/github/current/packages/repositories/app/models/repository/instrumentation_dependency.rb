# typed: true
# frozen_string_literal: true

module Repository::InstrumentationDependency
  extend T::Helpers

  include Instrumentation::Model

  requires_ancestor { Repository }

  def event_prefix
    :repo
  end

  def event_key
    :repo
  end

  def event_payload
    payload = {
      event_prefix => self,
      :visibility  => visibility.to_sym,
    }

    # Could be a user or org, determine event_prefix on instance
    payload[T.must(owner).event_prefix] = owner if owner.present?

    if parent_id && parent
      payload[:fork_parent] = parent
    end

    if network && root != parent
      payload[:fork_source] = root
    end

    payload
  end

  def event_context(prefix: :repo)
    {
      prefix => name_with_display_owner,
      "#{prefix}_id".to_sym => id,
      "public_repo".to_sym => public?,
    }
  end

  def instrument_creation
    payload = {}

    if created_by.present?
      payload[:actor] = created_by
    end

    instrument :create, payload

    hydro_payload = {
      actor: created_by,
      repository: self,
      gitignore_template: gitignore_template,
      license_template: license_template,
      init_with_readme: auto_init,
      owner: owner,
    }

    hydro_payload[:parent] = parent if fork?

    GlobalInstrumenter.instrument "repository.create", hydro_payload
  end

  def instrument_default_branch_update(branch:, old:)
    payload = {
      actor: actor,
      changes: {
        default_branch: branch,
        old_default_branch: old
      }
    }

    instrument :update, payload
    instrument :update_default_branch, payload
  end

  def instrument_initial_push
    payload = {
      actor: actor,
      changes: {
        default_branch: default_branch
      }
    }

    instrument :initial_push, payload
  end

  def instrument_search_default_branch_update(new_ref)
    payload = {
      change: :DEFAULT_BRANCH_CHANGED,
      repository: self,
      owner_name: self.owner&.name,
      updated_at: Time.now.utc,
      ref: new_ref,
    }

    GlobalInstrumenter.instrument("search_indexing.repository_changed", payload)
    GitHub.dogstats.increment("geyser.repo_changed_event.published", tags: ["change_type:default_branch_changed"])
  end

  def instrument_update
    changes = {}.tap do |hash|
      if previous_changes.has_key?("description")
        hash[:old_description] = previous_changes["description"].first
        hash[:description] = description
      end
      if previous_changes.has_key?("homepage")
        hash[:old_homepage] = previous_changes["homepage"].first
        hash[:homepage] = homepage
      end
    end

    unless changes.empty?
      instrument :update, actor: actor, changes: changes
      GlobalInstrumenter.instrument("repository.details_updated", {
        actor: actor,
        repository: self,
        description: changes[:description],
        homepage: changes[:homepage],
      })
    end
  end

  # Public: Log an audit log event when the repository is opted out of or back into being available
  # to recommend to users via the "Discover repositories" page.
  def instrument_repository_recommendations_change(opt_out:, actor:)
    key = opt_out ? :opt_out_of_recommendations : :opt_into_recommendations
    instrument(key, actor: actor)
  end

  def instrument_transfer(new_owner:, old_owner:, old_nwo:, actor:)
    outgoing_params = {
      repo: old_nwo,
      repo_id: id,
      new_nwo: nwo,
      public_repo: public?,
      visibility: visibility.to_sym,
    }

    # Instrument this event in the previous owner's audit log
    outgoing_params = outgoing_params.merge(old_owner.event_context)
    outgoing_params = outgoing_params.merge(new_owner.event_context(prefix: :new_owner))

    if pending_transfer.present?
      # The actor here is the user who initiated the transfer – not the user
      # that accepted it (which is what the `actor` kwarg is)
      outgoing_params[:actor] = pending_transfer.requester
    end

    # We use `GitHub.instrument` here instead of just `instrument` because we
    # want to instrument this for the previous owner's audit log
    GitHub.instrument("repo.transfer_outgoing", outgoing_params)

    instrument :transfer, {
      actor: actor,
      old_user: old_owner,
      owner: new_owner,
      owner_is_org: new_owner.organization?,
      owner_was_org: old_owner.organization?,
      repo_was: old_nwo,
      repo: self,
    }
  end
end
