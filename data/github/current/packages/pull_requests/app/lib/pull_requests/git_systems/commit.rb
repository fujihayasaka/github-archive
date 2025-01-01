# typed: strict
# frozen_string_literal: true

module PullRequests
  module GitSystems
    module Commit
      extend T::Helpers
      include Kernel

      interface!
      sealed!

      class Created < T::Struct
        extend T::Sig

        include Commit

        const :sha, String
        alias oid sha

        const :base_sha, String
        alias base_oid base_sha

        const :head_sha, String
        alias head_oid head_sha

        sig { returns([String, String]) }
        def parent_shas = [base_sha, head_sha]
        alias parent_oids parent_shas
      end

      class Conflict < T::Struct
        extend T::Sig

        include Commit

        const :details, T.nilable(T.any(T::Hash[T.untyped, T.untyped], {
          conflicted_files: T::Hash[String, T::Hash[Symbol, T.untyped]],
          more_conflicted_files: T::Boolean,
        }))

        # List of file names returned within the conflict payload.
        sig { returns(T::Array[String]) }
        def file_names
          (details&.dig(:conflicted_files) || {}).keys
        end
      end

      class Failed < T::Struct
        include Commit

        const :code, T.nilable(Symbol)
      end

      class Error < T::Struct
        include Commit

        const :exception, Exception
      end
    end
  end
end
