# typed: true
# frozen_string_literal: true

module ProgrammaticAccess
  module AccessibleRepositoriesDependency
    DEFAULT_BATCH_SIZE = 1000
    METADATA = "metadata"

    # Public: Given an array of repository ids return
    # the list of repositories the PAT has access to.
    #
    #  target:                   A target record that can be used to further limit the result.
    #  repository_ids:           An array of repository ids.
    #  resource:                 A resource to limit results to repository ids with permissions on this resource.
    #
    # Returns an Array of repository ids.
    def accessible_repository_ids(target: nil, repository_ids: [], resource: METADATA)
      T.bind(self, UserProgrammaticAccess)

      GitHub.tracer.in_span("programmatic_access.accessible_repository_ids", kind: :internal) do |span|
        span.add_attributes("gh.programmatic_actor_filter.resource" => resource.to_s, "gh.programmatic_actor_filter.repositories.count" => repository_ids.count)

        return [] if repository_ids.none?
        return [] if Repository::Resources.all_type_prefixed_subject_types([resource]).none?

        # We don't yet support multiple grants on the same PAT, so we
        # can make assumptions like the one below.
        return [] unless grant
        return [] if target && grant.target != target

        grant.repository_ids(resource: resource, repository_ids: repository_ids)
      end
    end
  end
end
