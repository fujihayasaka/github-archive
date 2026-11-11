# typed: true
# frozen_string_literal: true

module DependencyGraph
  class ReassignPackageMutation < Query
    def initialize(package_manager:, package_name:, repository_id:, backend: nil)
      @package_manager    = package_manager
      @package_name       = package_name
      @repository_id      = repository_id

      super(backend: backend)
    end

    def execute
      post_mutation.map { |response| Result.new(response) }
    end

    # we inherit from DependencyGraph::Query, which requires us to implement this
    # method (abstract method in Sorbet)
    def query(options = {}); end

    private

    attr_reader :package_manager, :package_name, :repository_id

    def variables
      {
        input: {
          packageManager:   package_manager,
          packageName:      package_name,
          repositoryId:     repository_id,
        },
      }
    end

    def post_mutation
      backend.post <<~MUTATION, variables
        mutation($input: ReassignPackageInput!) {
          reassignPackage(input: $input) {
            __typename # don't need anything here
          }
        }
      MUTATION
    end

    class Result
      def initialize(response)
        @response = response
      end
    end
  end
end
