# typed: strict
# frozen_string_literal: true

module Repositories
  class Domain
    class Diffs < GH::Domain::Base
      # Public: Determine where paths line numbers have moved between two commitish OIDs. Commits must exist or the
      # request will not succeed.
      #
      # source_oid - A committish for the base comparison commit.
      # target_oid - A committish for a tip to compare against the base.
      # repository - The repository containing the git objects.
      # targets    - A hash of path => [line_numbers] for each positioning requested. At least one line number is required.
      sig do
        params(
          repository: IRepository,
          source_oid: String,
          target_oid: String,
          targets: T::Hash[String, T::Array[Integer]]
        ).returns(T.any(
          GH::Result::Ok[T::Hash[String, T.any(
            { target_path: String, lines: T::Hash[Integer, Integer] },
            SpokesAPI::Types::DiffPositionState,
          )]],
          GH::Result::Error[String],
          GH::Result::Error::NotFound[NilClass],
          GH::Result::Error::Argument[String],
          GH::Result::Error::ServiceRateLimited[String],
          GH::Result::Error::ServiceUnreachable[String],
        ))
        .checked(:always)
        .on_failure(:raise)
      end
      def diff_positions(repository:, source_oid:, target_oid:, targets:) # rubocop:todo Metrics/MethodLength
        repository = T.cast(repository, Repository) # rubocop:todo GitHub/AvoidCast

        begin
          response = repository.spokes_api.get_diff_positions(
            source_oid:,
            target_oid:,
            source_items: targets.map { |name, line_numbers| { source_path: { name: }, line_numbers: } }
          )
        rescue SpokesAPI::NotFound => exception
          return GH::Result::Error::NotFound.new(exception.message)
        rescue SpokesAPI::ResourceExhausted => exception
          return GH::Result::Error::ServiceRateLimited.new(exception.message)
        rescue SpokesAPI::TwirpServerError, SpokesAPI::TimedOut, SpokesAPI::Canceled, SpokesAPI::TwirpConnectionError => exception
          return GH::Result::Error::ServiceUnreachable.new(exception.message)
        end

        if response.is_a?(String)
          GH::Result::Error.new(response)
        else
          value = response.each_with_object({}) do |payload, value|
            source_path = payload.dig(:source_path, :name)
            source_lines = targets[source_path] || []

            case state = payload[:state]
            when SpokesAPI::Types::DiffPositionState::Success
              value[source_path] = {
                lines: payload.fetch(:line_numbers, []).to_h { _1.values_at(:source_line_number, :target_line_number) },
                target_path: payload.dig(:target_path, :name),
              }
            else
              value[source_path] = state
            end
          end

          GH::Result::Ok.new(value)
        end
      end
    end
  end
end
