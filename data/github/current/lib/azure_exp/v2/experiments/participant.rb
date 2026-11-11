# typed: strict
# frozen_string_literal: true

module AzureEXP
  module V2
    module Experiments
      # Typed randomization unit for treatment assignments.
      #
      # The Go SDK and TAS REST API accept a flat `userParams` hash
      # (map[string]string). This class adds a typed layer on top to
      # prevent key typos and make call sites self-documenting.
      #
      # Usage:
      #
      #   participant = AzureEXP::V2::Experiments::Participant.user(current_user)
      #   AzureEXP::V2::Experiments.current.add_participant(participant)
      #
      #   participant = AzureEXP::V2::Experiments::Participant.repository(repo)
      #   AzureEXP::V2::Experiments.current.add_participant(participant)
      #
      class Participant
        extend T::Helpers

        # Conventional userParams key names for the ExP config.
        # These must match the interned param ids in the ExP workspace; once
        # created the ids do not change. See:
        #   https://devportal.githubapp.com/exp/assignment-units
        #   https://devportal.githubapp.com/exp/audience-filters
        # The user randomization unit is keyed by `copilottrackingid` and
        # carries the user's analytics tracking id (not the database user id),
        # matching the existing AzureEXP usage.
        UNIT_USER = "copilottrackingid"
        UNIT_REPO = "repo_id"
        UNIT_PR = "pr_id"

        sig { returns(String) }
        attr_reader :key

        sig { returns(String) }
        attr_reader :value

        sig { params(key: String, value: String).void }
        def initialize(key:, value:)
          raise ArgumentError, "key must not be empty" if key.empty?
          raise ArgumentError, "value must not be empty" if value.empty?

          @key = T.let(key, String)
          @value = T.let(value, String)
        end

        # Builds a user randomization unit, or nil when there is no user to
        # randomize on. Returns nil for anonymous/logged-out traffic (user is
        # nil) and for a user with no analytics tracking id yet.
        #
        # Returning nil lets callers pass the result straight to
        # add_participant without guarding current_user themselves: the user
        # dimension is simply absent and assignment falls back to any other
        # units present (or to caller defaults). This mirrors the Go client,
        # where a missing userParams key just means that dimension is not used
        # for bucketing, and keeps the wrapper from ever raising into a request
        # for the routine case of logged-out traffic.
        sig { params(user: T.untyped).returns(T.nilable(AzureEXP::V2::Experiments::Participant)) }
        def self.user(user)
          return nil if user.nil?

          tracking_id = user.analytics_tracking_id
          if tracking_id.nil? || tracking_id.empty?
            # A present user with no tracking id is unexpected (anonymous
            # traffic is handled by the nil check above), so surface it rather
            # than silently dropping the unit.
            GitHub.dogstats.increment("monolith.experiments.participant.skipped", tags: ["unit:user"])
            return nil
          end

          new(key: UNIT_USER, value: tracking_id)
        end

        sig { params(repository: T.untyped).returns(AzureEXP::V2::Experiments::Participant) }
        def self.repository(repository)
          new(key: UNIT_REPO, value: repository.id.to_s)
        end

        sig { params(pull_request: T.untyped).returns(AzureEXP::V2::Experiments::Participant) }
        def self.pull_request(pull_request)
          new(key: UNIT_PR, value: pull_request.id.to_s)
        end

        # For custom or future randomization units not covered above.
        sig { params(key: String, value: String).returns(AzureEXP::V2::Experiments::Participant) }
        def self.custom(key:, value:)
          new(key: key, value: value)
        end

        # Returns the key-value pair for inclusion in the userParams hash.
        sig { returns(T::Array[String]) }
        def to_pair
          [key, value]
        end
      end
    end
  end
end
