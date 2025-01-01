# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioner
      module Loaders
        # Efficiently validates blob existence using batched SpokesAPI calls to minimize
        # expensive network operations to the Git object store.
        #
        # The BlobValidations loader handles:
        # - Batching blob existence checks for multiple commit/path combinations
        # - Managing validation state (Unresolved, Found, NotFound) for each request
        # - Executing SpokesAPI queries with comprehensive error handling
        # - Providing fast lookup of validation results after batch processing
        #
        # Network errors are handled gracefully with retry-friendly behavior, ensuring
        # robust operation even under adverse conditions.
        class BlobsAndLines
          # Represents the validation state of a blob existence check.
          class Request < T::Struct
            module State
              extend T::Helpers
              include Kernel

              sealed!

              class Unresolved
                include State
              end

              class Resolved < T::Struct
                include State
                const :oid, String
              end

              class ResolvedWithLines < T::Struct
                include State

                const :oid, String
                const :lines, Integer
              end

              class NotFound
                include State

                Instance = T.let(new, NotFound)
              end
            end

            const :commit_oid, String
            const :path, String
            prop  :include_lines, T::Boolean, default: false
            prop  :state, State, default: State::Unresolved.new

            sig { returns(T::Hash[Symbol, T.untyped]) }
            def to_spokes_selector
              {
                by_treeish_and_path: {
                  treeish: { oid: { id: commit_oid } },
                  path: { name: T.must(SpokesAPI::Util.normalize_path(path)) }
                }
              }
            end

            sig { returns(T::Boolean) }
            def unresolved? = state.is_a?(State::Unresolved)
          end

          sig { params(repository: Repository).void }
          def initialize(repository:)
            @repository = repository
            @requests = T.let(Set.new, T::Set[Request])
          end

          # Append a request to the batch loading. If a line number is included, it will result in querying CountLines
          # to determine if the line number is valid for the given commit/path combination.
          sig { params(commit_oid: String, path: String, line: T.nilable(Integer)).void }
          def add_to_batch(commit_oid:, path:, line:)
            request = @requests.find { _1.unresolved? && _1.path == path && _1.commit_oid == commit_oid } || Request.new(commit_oid:, path:)

            unless line.nil?
              request.include_lines = true
            end

            @requests << request
          end

          # Execute batched blob validation for all pending requests using SpokesAPI/GitRPC.
          sig { void }
          def load_batch!
            # Build SpokesAPI selectors for all unresolved blob requests
            selectors = @requests.select(&:unresolved?)

            # Skip SpokesAPI call if no unresolved requests remain
            return if selectors.empty?

            # Execute the batched SpokesAPI call with error handling.
            response = begin
              @repository.spokes_api.resolve_objects_by(selectors.map(&:to_spokes_selector))
            rescue SpokesAPI::NotFound
              # This error means that none of the requested objects were found.
              # We can mark all of them as NotFound.
              selectors.each { |request| request.state = Request::State::NotFound::Instance }

              return
            rescue SpokesAPI::Error, GitRPC::Error, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError
              # TODO: Should we support retrying or just fail?
              return
            end

            # Mark all requested blobs as NotFound by default. We'll update the found ones in the next step.
            selectors.each { |request| request.state = Request::State::NotFound::Instance }

            # Process SpokesAPI response and update validation states based on object types.
            T.let(
              response.items.to_a,
              T::Array[GitHub::Spokes::Proto::Objects::V1::ResolveObjectsResponse::ResolvedItem]
            ).each_with_index do |item, index|
              next unless request = selectors[index]

              type = item.object&.type
              oid = item.object&.oid

              # Mark as Found only if the resolved object is actually a blob
              if type == :TYPE_BLOB && oid
                request.state = Request::State::Resolved.new(oid: oid.id)
              end
            end

            # Generate a mapping of blob object_ids to Requests for later lookup.
            oids = T.let({}, T::Hash[String, Request])

            # Determine which requests are pending and needing the lines to be resolved.
            @requests.each do |request|
              case state = request.state
              when Request::State::Resolved
                if request.include_lines
                  oids[state.oid] = request
                end
              end
            end

            # Skip calling this RPC if we don't have any CountLines to resolve.
            return if oids.empty?

            # Call in to the GitRPC version of count_lines to determine the total number of lines in the file.
            # TODO: When the CountLines Spokes RPC is available, utilize that instead.
            begin
              result = T.let(
                @repository.rpc.count_lines(oids.keys), T::Hash[String, T.nilable(Integer)]
              )
            rescue => exception
              Failbot.report(exception)
              # Since we've partially resolved at this point, continue on and let the validations fail for line numbers.
              return
            end

            # Update the loaded requests for line numbers.
            @requests.each do |request|
              case state = request.state
              when Request::State::Resolved
                case lines = result[state.oid]
                when Integer
                  request.state = Request::State::ResolvedWithLines.new(oid: state.oid, lines:)
                end
              end
            end
          end

          # Determine if the given path/commit exists and is valid within git. Optionally, a line number can be validated
          # for line-based positioning.
          sig { params(commit_oid: String, path: String, line: T.nilable(Integer)).returns(T.any(TrueClass, Errors::Line, Errors::Path)) }
          def resolve(commit_oid:, path:, line:)
            # Look for any resolved request that could match this commit/path.
            request = @requests.find { _1.unresolved? == false && _1.path == path && _1.commit_oid == commit_oid }

            return Errors::Path.new(path:) if request.nil?

            state = request.state

            if state.is_a?(Request::State::NotFound) || state.is_a?(Request::State::Unresolved)
              # When we cannot resolve the path at all, nothing about the blob/path pair is valid.
              Errors::Path.new(path:)
            elsif line.nil?
              # When validating file level comments, the paths existing makes this valid.
              true
            elsif state.is_a?(Request::State::Resolved)
              # When validating line level comments, the line numbers must be resolvable.
              Errors::Line.new(line:)
            else
              # Finally, the line number must be less than or equal to the total number of lines for the path.
              if line <= state.lines
                true
              else
                Errors::Line.new(line:)
              end
            end
          end
        end
      end
    end
  end
end
