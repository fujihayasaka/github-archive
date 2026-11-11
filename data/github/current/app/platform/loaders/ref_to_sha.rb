# typed: strict
# frozen_string_literal: true

module Platform
  module Loaders
    # TODO - GitRPC doesn't have any batch rev-parse functionality at
    # the moment. When we implement that this should batch requests.
    class RefToSha < Platform::Loader
      sig do
        params(
          repository: Repositories::IRepository,
          expression: String
        ).returns(Promise[T.nilable(Commit)])
      end
      def self.load(repository, expression)
        T.cast(repository, Repository).async_network.then do # rubocop:todo GitHub/AvoidCast
          self.for(repository).load(expression)
        end
      end

      sig { params(repository: Repositories::IRepository).void }
      def initialize(repository)
        @repository = T.let(T.cast(repository, Repository), Repository) # rubocop:todo GitHub/AvoidCast
      end

      private

      sig do
        params(
          expressions: T::Array[String]
        ).returns(T::Hash[String, T.nilable(Commit)])
      end
      def fetch(expressions)
        expressions.each_with_object({}) do |expression, results|
          begin
            if oid = @repository.ref_to_sha(expression)
              path_prefix = ::Commit.extract_path_prefix_from_expression(expression)
              results[expression] = GitObject.load(@repository, oid, path_prefix: path_prefix)
            end
          rescue GitHub::DGit::UnroutedError
            results[expression] = nil
          end
        end
      end
    end
  end
end
