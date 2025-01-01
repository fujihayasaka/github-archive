# typed: strict
# frozen_string_literal: true

# Performs instrumentation of repositories added or removed from an
# IntegrationInstallation asynchronously because sometimes a large number of
# repos are involved in an installation change, which can cause a timeout in a
# normal web request.
class IntegrationInstallationInstrumentationJob < ApplicationJob
  extend T::Sig

  queue_as :integration_installation_instrumentation

  retry_on_dirty_exit

  sig do
    params(
      action: Symbol,
      installation_id: Integer,
      actor_id: Integer,
      repository_ids: T::Array[Integer],
      repository_selection: String,
      requester_id: T.nilable(Integer)
    ).void
  end
  def perform(action, installation_id, actor_id, repository_ids, repository_selection, requester_id: nil)
    installation = IntegrationInstallation.where(id: installation_id).first
    actor = User.where(id: actor_id).select(:id, :login, :display_login, :type).first

    return if installation.blank? || actor.blank?

    options = {
      actor: actor,
      async: false, # Do it synchronously so we don't recursively enqueue this job
    }

    case action
    when :repositories_added
      options[:repository_selection] = repository_selection
      options[:requester_id]         = requester_id if requester_id

      options[:performed_automatically] = true if actor.bot?

      installation.instrument_repositories_added(repository_ids, repository_selection:, **options)
    when :repositories_removed
      installation.instrument_repositories_removed(repository_ids, **options)
    end
  end
end
