# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class CommittableBranch < Platform::Inputs::Base
      graphql_name "CommittableBranch"
      description <<~MARKDOWN
        A git ref for a commit to be appended to.

        The ref must be a branch, i.e. its fully qualified name must start
        with `refs/heads/` (although the input is not required to be fully
        qualified).

        The Ref may be specified by its global node ID or by the
        `repositoryNameWithOwner` and `branchName`.

        ### Examples

        Specify a branch using a global node ID:

            { "id": "MDM6UmVmMTpyZWZzL2hlYWRzL21haW4=" }

        Specify a branch using `repositoryNameWithOwner` and `branchName`:

            {
              "repositoryNameWithOwner": "github/graphql-client",
              "branchName": "main"
            }

      MARKDOWN

      argument :id, ID, "The Node ID of the Ref to be updated.", required: false
      argument :repository_name_with_owner, String, "The nameWithOwner of the repository to commit to.", required: false
      argument :branch_name, String, "The unqualified name of the branch to append the commit to.", required: false

      # Overriding this method to customize what it means for this input to be null
      # validation_options is a hash with keys: max_errors
      # see: https://graphql-ruby.org/errors/overview.html#validation-errors
      def self.validate_non_null_input(value, ctx, _validation_options = {})
        unless value.instance_of?(Hash)
          result = GraphQL::Query::InputValidationResult.new
          result.add_problem("bad type")
          return result
        end

        id, nwo, branch = value.values_at("id", "repositoryNameWithOwner",  "branchName")
        return super(value, ctx) if  id && !nwo && !branch
        return super(value, ctx) if !id && nwo && branch
        result = GraphQL::Query::InputValidationResult.new
        result.add_problem("either `id` or `repositoryNameWithOwner,branchName` must be passed")
        result
      end
    end
  end
end
