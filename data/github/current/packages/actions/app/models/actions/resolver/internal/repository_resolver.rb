# typed: true
# frozen_string_literal: true

class Actions::Resolver::Internal::RepositoryResolver
  extend T::Sig

  def initialize(metric_namespace:, metric_tags:)
    @metric_namespace = metric_namespace
    @metric_tags = metric_tags
  end

  sig do
    params(
      repo: Repository,
      requested_nwo: String,
      processed_nwo: T.nilable(String),
      ref: String,
    ).returns(T.any(Actions::Resolver::Internal::ResolvedAction, Actions::Resolver::Internal::Error))
  end
  def resolve(repo:, requested_nwo:, processed_nwo:, ref:)
    GitHub.dogstats.time("#{@metric_namespace}.actions.repository_resolver.resolve.time", tags: @metric_tags) do
      # NOTE: This logic doesn't make a lot of sense as we're ignoring any redirects if processing of the nwo occured before.
      # This is by accident and only has been disocvered recently. The current code flow is easier to follow than before and makes the problem clearer.
      requested_name = if processed_nwo
        # If there was processing done, use the requsted_nwo.
        requested_nwo
      else
        # If there was no processing done, we want to check for any redirects that might have happened.
        # If none happened, we can again use the requested_nwo.
        repo.redirects.first&.repository_name || requested_nwo
      end

      # Check to see if the repo owner is actions or for Enterprise, check to
      # see if it's the Actions org.
      repo_owner = T.must(repo.owner)
      if repo_owner.display_login == "actions" || (GitHub.enterprise? && repo_owner.display_login == GitHub.actions_org)
        if ref == "master"
          ref = "main"
        end
      end

      if ref.length == 40 && ref != ref.downcase && GitRPC::Util.valid_full_sha1?(ref.downcase)
        # Lowercase the SHA to avoid malicious tag/branch names that are an uppercase commit SHA
        raw_ref = ref
        ref = ref.downcase

        GitHub.logger.info("Forced to lowercase SHA",
          "code.namespace": "Actions::Resolver::Internal::RepositoryResolver",
          "code.function": "resolve",
          "gh.action.requested_nwo": requested_nwo,
          "gh.action.processed_nwo": processed_nwo,
          "gh.action.requested_name": requested_name,
          "gh.action.transformed_ref": ref,
          "gh.action.raw_ref": raw_ref)

        GitHub.dogstats.increment("actions.resolve_action.force_lowercase_sha", tags: @metric_tags)
      end

      # Ref and SHA could be a commit from a forked repository.
      # We will allow this to avoid breaking customers.
      # See https://github.com/github/c2c-actions-experience/issues/5087 for more details.
      sha = repo.ref_to_sha(ref)
      unless sha
        GitHub.dogstats.increment(
          "#{@metric_namespace}.actions.resolve_action",
          tags: ["error:unknown_ref"].concat(@metric_tags)
        )

        GitHub.logger.warn("Unable to resolve action due to unknown ref",
          "code.namespace": "Actions::Resolver::Internal::RepositoryResolver",
          "code.function": "resolve",
          "gh.action.requested_nwo": requested_nwo,
          "gh.action.processed_nwo": processed_nwo,
          "gh.action.requested_name": requested_name,
          "gh.action.transformed_ref": ref,
          "gh.action.raw_ref": raw_ref)

        return Actions::Resolver::Internal::Error.new(
          requested_name: requested_nwo,
          ref: ref,
          msg: "Unable to resolve action `#{requested_nwo}@#{ref}`, unable to find version `#{ref}`")
      end

      if !sha.casecmp?(ref) && sha.downcase.start_with?(ref.downcase)
        GitHub.dogstats.increment(
          "#{@metric_namespace}.actions.resolve_action",
          tags: ["error:blocked_short_sha"].concat(@metric_tags)
        )

        GitHub.logger.warn("Unable to resolve action due to short SHA ref",
          "code.namespace": "Actions::Resolver::Internal::RepositoryResolver",
          "code.function": "resolve",
          "gh.action.requested_nwo": requested_nwo,
          "gh.action.processed_nwo": processed_nwo,
          "gh.action.requested_name": requested_name,
          "gh.action.transformed_ref": ref,
          "gh.action.raw_ref": raw_ref,
          "gh.action.long_sha": sha)

        return Actions::Resolver::Internal::Error.new(
          requested_name: requested_nwo,
          ref: ref,
          msg: "Unable to resolve action `#{requested_nwo}@#{ref}`, the provided ref `#{ref}` is the shortened version of a commit SHA, which is not supported. Please use the full commit SHA `#{sha}` instead.")
      end

      repo_visibility = if repo.public?
        :PUBLIC
      elsif repo.private? && repo.visibility == Repository::PRIVATE_VISIBILITY
        :PRIVATE
      elsif repo.internal?
        :INTERNAL
      else
        :INVALID
      end

      GitHub.dogstats.increment(
        "#{@metric_namespace}.actions.resolve_action",
        tags: ["type:repository"].concat(@metric_tags)
      )

      # actions team will communicate any change in requirements to disambiguate display and unique name_with_owner in future.
      Actions::Resolver::Internal::ResolvedAction.new(
        id: repo.id,
        requested_name: requested_name,
        resolved_name: repo.name_with_display_owner,
        resolved_sha: sha,
        tar_url: "#{GitHub.api_url}/repos/#{repo.name_with_display_owner}/tarball/#{sha}",
        zip_url: "#{GitHub.api_url}/repos/#{repo.name_with_display_owner}/zipball/#{sha}",
        ref: ref,
        resolved_ref: ref,
        visibility: repo_visibility)
    end
  end
end
