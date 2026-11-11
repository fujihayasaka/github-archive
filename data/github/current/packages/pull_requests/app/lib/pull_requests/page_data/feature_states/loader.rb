# typed: strict
# frozen_string_literal: true

module PullRequests
  module PageData
    module FeatureStates
      # For simple user-level feature flags, we use the client feature flags directly in the UI
      # For more complex scenarios, we need to set them in the payload and manage them ourselves.
      #    - Note: This is because use of add_client_feature_flag is deprecated as it is not compatible with the UI Service
      #    - Common scenarios include:
      #      - When the feature flag state depends on multiple feature flags
      #      - When the feature flag depends on an actor check that isn't just the current user (e.g. repository-level, repository-owner, etc)
      #      - When the feature flag state needs to be represented from feature preview enrollment and/or availability
      class Loader
        include GitHub::ResilienceMixin
        include PullRequests::OverviewHelper

        class State < T::Enum
          enums do
            ENABLED = new("ENABLED")
            AVAILABLE = new("AVAILABLE")
            UNAVAILABLE = new("UNAVAILABLE")
          end
        end

        class Data < T::Struct
          const :overview, State
          const :pull_request_stacks, State
          const :pull_request_stacks_prevent_unstacking_locked_prs, State
        end

        FALLBACK = T.let(
          Data.new(
            overview: State::UNAVAILABLE,
            pull_request_stacks: State::UNAVAILABLE,
            pull_request_stacks_prevent_unstacking_locked_prs: State::UNAVAILABLE,
          ),
          Data,
        )

        sig do
          params(
            current_user: T.nilable(User),
            repository: T.nilable(Repository),
            params: T.any(T::Hash[Symbol, T.untyped], ActionController::Parameters),
          ).returns(Data)
        end
        def self.load(current_user:, repository: nil, params: {})
          new(current_user:, repository:, params:).load
        end

        sig do
          params(
            current_user: T.nilable(User),
            repository: T.nilable(Repository),
            params: T.any(T::Hash[Symbol, T.untyped], ActionController::Parameters),
          ).void
        end
        def initialize(current_user:, repository: nil, params: {})
          @current_user = current_user
          @repository = repository
          @params = params
        end

        sig { returns(Data) }
        def load
          with_database_error_fallback(fallback: FALLBACK) do
            pull_request_stacks_state = calculate_pull_request_stacks_state
            Data.new(
              overview: calculate_overview_state,
              pull_request_stacks: pull_request_stacks_state,
              pull_request_stacks_prevent_unstacking_locked_prs: calculate_pull_request_stacks_prevent_unstacking_locked_prs,
            )
          end
        end

        private

        sig { returns(State) }
        def calculate_overview_state
          if pr_overview_feature_enabled_for_user?(@current_user, @params)
            State::ENABLED
          elsif pr_overview_feature_flag_enabled_for_user?(@current_user)
            State::AVAILABLE
          else
            State::UNAVAILABLE
          end
        end

        sig { returns(State) }
        def calculate_pull_request_stacks_state
          if PullRequests::Stacks.enabled?(@repository)
            State::ENABLED
          else
            State::UNAVAILABLE
          end
        end

        sig { returns(State) }
        def calculate_pull_request_stacks_prevent_unstacking_locked_prs
          if FeatureFlag.vexi.enabled?(:pull_request_stacks_prevent_unstacking_locked_prs, @repository, default: false)
            State::ENABLED
          else
            State::UNAVAILABLE
          end
        end
      end
    end
  end
end
