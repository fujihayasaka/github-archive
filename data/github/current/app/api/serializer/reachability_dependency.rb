# typed: true
# frozen_string_literal: true

module Api::Serializer::ReachabilityDependency
  extend T::Helpers
  requires_ancestor { Api::Serializer::RepositoriesDependency }
  requires_ancestor { Api::Serializer::UserDependency }

  def reachability_advisories_hash(advisories, options = {})
    # TODO(https://github.com/github/team-reachability/issues/13): Implement an actual serializer
    [
      {
        ghsa_id: "GHSA-abcd-efgh-ijkl",
        vulnerabilities: [
          package: {
            ecosystem: "npm",
            name: "a-package"
          },
          first_patched_version: "1.0.3",
          vulnerable_version_range: "<=1.0.2",
          vulnerable_functions: [
            "a_function"
          ]
        ]
      }
    ]
  end

  def reachability_dependencies(graphs, options = {})
    # TODO(https://github.com/github/team-reachability/issues/13): Implement an actual serializer
    [
      {
        dependency_graph: "no graph found"
      }
    ]
  end
end
