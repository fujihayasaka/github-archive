# typed: true
# frozen_string_literal: true

class Actions::Resolver::V2::Internal::ActionsClassifier

  sig { params(metric_namespace: String, metric_tags: T::Array[String], workflow_repo: T.nilable(Repository), anonymous: T::Boolean, proxima_fallback_request: T::Boolean).void }
  def initialize(metric_namespace:, metric_tags:, workflow_repo: nil, anonymous: false, proxima_fallback_request: false)
    raise ArgumentError, "workflow_repo must be provided when anonymous is false" if !anonymous && workflow_repo.nil?
    raise ArgumentError, "workflow_repo must not be provided when anonymous is true" if anonymous && !workflow_repo.nil?

    @metric_namespace = metric_namespace
    @metric_tags = metric_tags
    @workflow_repo = workflow_repo
    @anonymous = anonymous
    @proxima_fallback_request = proxima_fallback_request

    @deprecated_actions_filter = Actions::Resolver::Internal::DeprecatedActionsFilter.new(workflow_repo: workflow_repo, connect_request: anonymous, proxima_fallback_request: proxima_fallback_request)
  end

  # This method does NOT maintain the order of the actions.
  # This method may return an action collection containing less actions than provided in case of duplicates.
  # The collection can be directly used to resolve actions, however, consumers should index the resolved actions
  # by the nwo and raw ref and then use the index to retrieve the resolved action for each input action.
  sig { params(actions: T::Array[Actions::Resolver::V2::Internal::ActionsCollection::Action]).returns(Actions::Resolver::V2::Internal::ActionsCollection) }
  def classify(actions)
    start_time = GitHub::Dogstats.monotonic_time
    talked_to_package_registry = false

    # We're deduplicating the actions here to reduce the number of actions we send to RMS and GHCR.
    # Note that we still send both actions in scenarios like `v1` and `1.*`
    # where both are passed as `1.*` to RMS but they are not equal.
    # This is on purpose as we want a result for both `v1` and `1.*` to exists in the collection.
    actions = actions.uniq

    # Collection splits the actions into repository and semver actions
    collection = Actions::Resolver::V2::Internal::ActionsCollection.new(actions)

    # `unclassified_semver_actions` returns cloned array.
    # This is important as without cloning, we would modify the collection while iterating over it.
    collection.unclassified_semver_actions.each do |action|
      # Check if FF to serve this as package has been enabled.
      # Note that the FF is only checked on the resolved_nwo.
      # In GHES this means that with custom `actions` or `github` orgs,
      # the FF is only checked on those custom orgs and not on the `github` or `actions` org.
      owner_name = action.resolved_nwo.split("/").first # rubocop:disable GitHub/DoNotAllowNameWithOwner
      owner = User.find_by(login: owner_name)
      serving_ff_enabled_enabled_for_owner = false
      serving_ff_enabled_enabled_for_repo = false

      # `anonymous` means we're serving a GitHub Connect/Proxima Fallback request.
      serving_ff_name = if @anonymous
        if @proxima_fallback_request
          :serve_immutable_actions_over_connect_proxima
        else
          :serve_immutable_actions_over_connect_ghes
        end
      else
        :serve_immutable_actions
      end

      # Uses with_name_with_owner to exclude renamed repositories.
      serving_ff_enabled_enabled_for_owner = owner&.feature_flag_enabled_or_raise?(serving_ff_name) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      if !serving_ff_enabled_enabled_for_owner
        serving_ff_enabled_enabled_for_repo = Repository.with_name_with_owner(action.resolved_nwo)&.feature_flag_enabled?(serving_ff_name, default: false)
      end

      # If the FF is not enabled we're going to serve this as a repository.
      # This even happens in the case were RMS would normally tell us that the package action exists but no matching version.
      # Usually we would never fallback to repositories in that case since that's an attack vector.
      #
      # We're doing this classification **before** sending the semver actions to RMS.
      # This ensures we don't even talk to RMS if non of the actions have the FF enabled.
      if serving_ff_enabled_enabled_for_owner || serving_ff_enabled_enabled_for_repo
        serving_ff_actor_type = serving_ff_enabled_enabled_for_owner ? "owner" : "repository"

        GitHub.dogstats.increment(
          "#{@metric_namespace}.actions.classify.kept_as_unclassified_ref_due_to_ff_enabled",
          tags: [
            "serving_ff_name:#{serving_ff_name}",
            "serving_ff_actor_type:#{serving_ff_actor_type}",
          ].concat(@metric_tags))

        GitHub.logger.info("Keeping action as unclassified ref due to FF enabled",
          "code.namespace": "Actions::Resolver::V2::Internal::ActionsClassifier",
          "code.function": "classify",
          "gh.action.requested_nwo": action.requested_nwo,
          "gh.action.resolved_nwo": action.resolved_nwo,
          "gh.action.ref": action.ref,
          "gh.action.normalised_semver": action.normalised_semver,
          "gh.actions.classify.serving_ff_name": serving_ff_name,
          "gh.actions.classify.serving_ff_actor_type": serving_ff_actor_type)
      else
        GitHub.dogstats.increment(
          "#{@metric_namespace}.actions.classify.forced_to_repository_ref_due_to_ff_disabled",
          tags: [
            "serving_ff_name:#{serving_ff_name}",
          ].concat(@metric_tags))

        GitHub.logger.info("Forcing action as repository ref due to FF disabled",
          "code.namespace": "Actions::Resolver::V2::Internal::ActionsClassifier",
          "code.function": "classify",
          "gh.action.requested_nwo": action.requested_nwo,
          "gh.action.resolved_nwo": action.resolved_nwo,
          "gh.action.ref": action.ref,
          "gh.action.normalised_semver": action.normalised_semver,
          "gh.actions.classify.serving_ff_name": serving_ff_name)

        collection.serve_semver_from_repository_ref!(nwo: action.requested_nwo, ref: action.ref)
      end
    end

    # We iterate over all unclassified semver actions and decide if they should be blocked before we attempt to resolve them via RMS.
    collection.unclassified_semver_actions.each do |action|
      if @deprecated_actions_filter.action_blocked?(requested_nwo: action.requested_nwo, ref: action.ref)
        collection.impossible_to_serve!(nwo: action.requested_nwo, ref: action.ref, error: :blocked_action)
      end
    end

    # We iterate over all repository actions and decide if they should be blocked before we attempt to classify them via RMS.
    collection.repository_actions.each do |action|
      if @deprecated_actions_filter.action_blocked?(requested_nwo: action.requested_nwo, ref: action.ref)
        collection.impossible_to_serve!(nwo: action.requested_nwo, ref: action.ref, error: :blocked_action)
      end
    end

    # `unclassified_semver_actions` returns cloned array so we'll store the result in a variable.
    # This is important as without cloning, we would modify the collection while iterating over it.
    actions_to_query_in_rms = collection.unclassified_semver_actions
    if actions_to_query_in_rms.any?
      talked_to_package_registry = true

      # Ask RMS to resolve all semver actions to full semvers.
      action_references = actions_to_query_in_rms.map do |action|
        # Disabled cop because `resolved_nwo` refers to the `nwo` attribute of the request we receive from launch.
        split_nwo = action.resolved_nwo.split("/") # rubocop:disable GitHub/DoNotAllowNameWithOwner
        {
          semver_ref: action.normalised_semver,
          namespace: split_nwo[0],
          name: split_nwo[1]
        }
      end
      resp = PackageRegistry::Twirp.action_packages_client.resolve_action_packages(
        action_references: action_references,
        workflow_repo_id: @workflow_repo&.id,
        anonymous: @anonymous)

      results = T.cast(resp.results.map { |r| PackageRegistry::Twirp::ActionPackages::Result.new(r) }, T::Array[PackageRegistry::Twirp::ActionPackages::Result])

      # Inspect RMS results and decide which semver actions:
      # - Should be served from packages.
      # - Are safe to be served from a repository ref.
      # - Can't be resolved in a safe way.
      results.each_with_index do |result, index|
        # RMS is guaranteed to return the results in the same order we provided our input.
        action = T.must(actions_to_query_in_rms[index])
        raw_ref = action.ref
        requested_nwo = action.requested_nwo
        if result.success?
          # Resolved

          GitHub.dogstats.increment(
            "#{@metric_namespace}.actions.classify.servable_from_package_version",
            tags: @metric_tags)

          GitHub.logger.info("Serving action as package ref due to RMS Result",
            "code.namespace": "Actions::Resolver::V2::Internal::ActionsClassifier",
            "code.function": "classify",
            "gh.action.requested_nwo": action.requested_nwo,
            "gh.action.resolved_nwo": action.resolved_nwo,
            "gh.action.ref": action.ref,
            "gh.action.normalised_semver": action.normalised_semver,
            "gh.action.full_semver": T.must(result.resolved_semantic_version_tag),
            "gh.action.package_id": T.must(result.resolved_package_id),
            "gh.action.package_visibility": T.must(result.resolved_package_visibility))

          collection.serve_semver_from_package_version!(
            nwo: requested_nwo,
            ref: raw_ref,
            full_semver: T.must(result.resolved_semantic_version_tag),
            package_id: T.must(result.resolved_package_id),
            package_visibility: T.must(result.resolved_package_visibility))
        else
          # Not resolved
          if result.fallback_to_repository_ref?
            GitHub.dogstats.increment(
              "#{@metric_namespace}.actions.classify.fallback_to_repository_ref",
              tags: @metric_tags)

            GitHub.logger.info("Serving action as repository ref due to RMS Result",
              "code.namespace": "Actions::Resolver::V2::Internal::ActionsClassifier",
              "code.function": "classify",
              "gh.action.requested_nwo": action.requested_nwo,
              "gh.action.resolved_nwo": action.resolved_nwo,
              "gh.action.ref": action.ref,
              "gh.action.normalised_semver": action.normalised_semver)

            collection.serve_semver_from_repository_ref!(nwo: requested_nwo, ref: raw_ref)
          else
            error = T.must(result.unrecoverable_error)

            GitHub.dogstats.increment(
              "#{@metric_namespace}.actions.classify.impossible_to_serve_due_to_rms_result",
              tags: @metric_tags)

            GitHub.logger.warn("Impossible to serve action due to RMS Result",
              "code.namespace": "Actions::Resolver::V2::Internal::ActionsClassifier",
              "code.function": "classify",
              "gh.action.requested_nwo": action.requested_nwo,
              "gh.action.resolved_nwo": action.resolved_nwo,
              "gh.action.ref": action.ref,
              "gh.action.normalised_semver": action.normalised_semver,
              "gh.actions.classify.error": error)

            collection.impossible_to_serve!(
              nwo: requested_nwo,
              ref: raw_ref,
              error: error)
          end
        end
      end
    end

    GitHub.dogstats.timing_since("#{@metric_namespace}.actions.classifier.classify.time", start_time, tags: [
      "talked_to_package_registry:#{talked_to_package_registry}",
    ].concat(@metric_tags))

    collection
  end
end
