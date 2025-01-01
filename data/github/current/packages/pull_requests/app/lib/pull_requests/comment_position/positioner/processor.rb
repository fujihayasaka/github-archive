# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioner
      # Side-effect free business logic layer for calling the repositioning RPC endpoints in a batched manner and parsing
      # the results.
      class Processor
        sig do
          params(
            requests: T::Array[Requests::Union],
            reader: IReader,
            max_attempts: Integer,
          ).void
        end
        def initialize(requests:, reader:, max_attempts: 3)
          @requests = requests
          @reader = reader
          @max_attempts = max_attempts
        end

        Result = T.type_alias { T.any(T::Hash[Requests::Union, Results::Union], Exception) }

        sig { returns(Result) }
        def call
          results = T.let({}, T::Hash[Requests::Union, Results::Union])

          @requests.each do |request|
            # Determine if we can reuse the already computed positional data.
            case request
            when Requests::File
              blob = request.blob

              if blob.up_to_date?
                results[request] = Results::File.new(
                  commit_oid: blob.commit_oid,
                  path: blob.path,
                  range: request.destination_range,
                  repositioned: false,
                )
              end
            when Requests::Line
              blob = request.blob

              if blob.up_to_date?
                results[request] = Results::Line.new(
                  range: request.destination_range,
                  commit_oid: blob.commit_oid,
                  path: blob.path,
                  line: blob.line,
                  repositioned: false,
                )
              end
            when Requests::Multiline
              start_blob = request.start_blob
              end_blob = request.end_blob

              if start_blob.up_to_date? && end_blob.up_to_date?
                results[request] = Results::Multiline.new(
                  range: request.destination_range,
                  start_commit_oid: start_blob.commit_oid,
                  start_path: start_blob.path,
                  start_line: start_blob.line,
                  end_commit_oid: end_blob.commit_oid,
                  end_path: end_blob.path,
                  end_line: end_blob.line,
                  repositioned: false,
                )
              end
            end
          end

          @requests.each do |request|
            # Skip loading already up to date requests.
            next if results.key?(request)

            case request
            when Requests::File, Requests::Line
              @reader.request(request.blob)
            when Requests::Multiline
              @reader.request(request.start_blob)
              @reader.request(request.end_blob)
            else T.absurd(request)
            end
          end

          begin
            @reader.call(max_attempts: @max_attempts)
          rescue => exception # rubocop:todo Lint/GenericRescue
            return exception
          end

          @requests.each do |request|
            # Skip updating already up to date requests.
            next if results.key?(request)

            results[request] = begin
              case request
              when Requests::File
                commit_oid, path, _ = @reader.fetch(request.blob)

                Results::File.new(commit_oid:, path:, range: request.destination_range)
              when Requests::Line
                commit_oid, path, line = @reader.fetch(request.blob)

                Results::Line.new(commit_oid:, path:, line:, range: request.destination_range)
              when Requests::Multiline
                start_commit_oid, start_path, start_line = @reader.fetch(request.start_blob)
                end_commit_oid, end_path, end_line = @reader.fetch(request.end_blob)

                Results::Multiline.new(
                  range: request.destination_range,
                  start_commit_oid:, start_path:, start_line:,
                  end_commit_oid:, end_path:, end_line:,
                )
              else T.absurd(request)
              end
            end
          end

          results
        end
      end
    end
  end
end
