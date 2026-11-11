# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# RepositoryDependencyFindPushJob is responsible for loading a Push for a set of git co-ordinates
# to feed into the RepositoryDependencyManifestChangedJob if it contains manifest changes.
#
# This job exists as a bridge between One Pipeline's snapshot-driven events and our legacy Push-driven events that
# feed into Dependabot Alerts.
#
# Once we have fully migrated all ecosystems to One Pipeline, this job and `RepositoryDependencyManifestChangedJob`
# can be retired in favour of using the `Dependabot#manifests_changed` entry point directly.
#
# There are two paths through this job depending on whether or not a `dependabot_event_id` is provided:
# - With a `dependabot_event_id` the Push is relayed to `RepositoryDependencyManifestChangedJob` without further
#   inspection since DS-API has detected manifest changes for us.
# - Without a `dependabot_event_id` we check the legacy `Push#dependency_manifest_changed?` method  to determine if
#   changes to non-DS-API ecosystems are present. `RepositoryDependencyManifestChangedJob` is only enqueued if this
#   is true.
class RepositoryDependencyFindPushJob < ApplicationJob
  class PushNotFound < StandardError; end

  queue_as :repository_dependencies

  retry_on_dirty_exit
  retry_on_recoverable_exceptions
  retry_on SpokesAPI::ResourceExhausted, wait: :polynomially_longer
  retry_on PushNotFound, attempts: 10, wait: :polynomially_longer

  # Since we operate on a single repository at a time, we resolve the tenant that way.
  # The arguments to the block are the arguments passed to the job.
  resolve_tenant_context do |args|
    Repositories::Public.resolve_tenant(id: args[:repository_id])
  end

  def perform(repository_id:, ref:, sha:, dependabot_event_id: nil)
    push = Repositories.domain.pushes.latest_by_after_and_ref(
      repository_id: repository_id,
      ref: ref,
      after: sha,
    )

    # DS-API consumes 'post-receive' events when commits are ingested which means we act in parallel to the Push
    # being stored in the database.
    #
    # In the event of a fast-path execution in DS-API, we can occasionally hand back the event before the Push
    # is present in all replicas and since we started in parallel we cannot provide the WaitForReplication helper
    # our timestamp as it can precede the Push being written.
    #
    # We raise here so the job will be retried with a polynomial backoff to guarantee Push lookup unless there is
    # a catastrophic failure.
    raise PushNotFound, "No push found for repository_id=#{repository_id} ref=#{ref} sha=#{sha}" if push.nil?

    if dependabot_event_id
      RepositoryDependencyManifestChangedJob.perform_later(push.id, repository_id, { dependabot_event_id: })
    else
      # NOTE: This method bypasses Repositories.domain access on purpose.
      #
      # We need to use Push#dependency_manifest_changed? which isn't available via the Repositories::Push
      # model intentionally.
      #
      # Push#dependency_manifest_changed? is something we are aiming to deprecate as part of this work by
      # shifting responsibility for change file analysis to DG services outside the monolith.
      push_model = Push.find_by(id: push.id) # domain-isolation-query-violation:ignore:packages/repositories (SELECT)

      # We're reloading an object we already have so this should never happen, but let's avoid any silent failures
      # if somehow encounter a split brain problem between the model and the domain interface.
      raise PushNotFound, "No push found for repository_id=#{repository_id} ref=#{ref} sha=#{sha}" unless push_model

      if push_model.initial_commit? || push_model.dependency_manifest_changed?
        RepositoryDependencyManifestChangedJob.perform_later(push.id, repository_id)
      end
    end
  end
end
