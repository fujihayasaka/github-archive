# typed: strict
# frozen_string_literal: true

class PullRequest
  class Icon
    extend T::Sig

    AnyPullRequest = T.type_alias do
      T.any(
        PullRequest,
        PlatformTypes::PullRequest,
        Issue::Adapter::CrossReferenceSourcePullRequestAdapter,
        Hovercard::Adapter::HovercardAdapter,
      )
    end

    class State < T::Enum
      extend T::Sig

      enums do
        Open = new(:open)
        Merged = new(:merged)
        Closed = new(:closed)
        Queued = new(:queued)
        Draft = new(:draft)
      end

      sig { params(pull_request: AnyPullRequest, permit_queued_icon: T::Boolean).returns(T.nilable(State)) }
      def self.for_pull_request(pull_request, permit_queued_icon: true)
        state = pull_request.state.downcase.to_sym
        return State.try_deserialize(state) unless state == :open

        # Checking if the PR is queued requires additional models to be
        # loaded. Let's avoid checking it if we don't have to:
        #
        # 1. We should try other, cheaper states first.
        # 2. We provide the `permit_queued_icon` option as an escape hatch
        #    for places where it's too expensive.
        #
        # Ideally `permit_queued_icon` will only be a temporary measure as
        # we adopt usage of this new `PullRequest::Icon` class and work out
        # any N+1 problems that are introduced.

        case pull_request
        when PullRequest
          return Draft if pull_request.draft?
          return Queued if permit_queued_icon && !!pull_request.in_merge_queue?
        when PlatformTypes::PullRequest
          return Draft if pull_request.is_draft
          return Queued if permit_queued_icon && pull_request.is_in_merge_queue
        when Issue::Adapter::CrossReferenceSourcePullRequestAdapter, Hovercard::Adapter::HovercardAdapter
          return Draft if pull_request.is_draft?
          return Queued if permit_queued_icon && pull_request.is_in_merge_queue?
        else
          begin
            T.absurd(pull_request)
          rescue TypeError
            # We want a type error in static checking, but to
            # gracefully fail at runtime.
          end
        end

        State::Open
      end

      sig { returns(String) }
      def to_s
        serialize.to_s
      end
    end

    sig { params(pull_request: AnyPullRequest, permit_queued_icon: T::Boolean).void }
    def initialize(pull_request, permit_queued_icon: true)
      @state = T.let(State.for_pull_request(pull_request, permit_queued_icon:), T.nilable(State))
    end

    sig { returns(T::Boolean) }
    def valid?
      @state.present?
    end

    sig { returns(String) }
    def short_label
      return "" if @state.nil?
      @state.to_s.capitalize
    end

    sig { returns(String) }
    def label
      case @state
      when State::Closed
        "Closed Pull Request"
      when State::Merged
        "Merged Pull Request"
      when State::Open
        "Open Pull Request"
      when State::Draft
        "Draft Pull Request"
      when State::Queued
        "Pull Request in Merge Queue"
      when nil
        "Pull Request"
      else
        T.absurd(@state)
      end
    end

    sig { returns(Symbol) }
    def primer_color
      case @state
      when State::Closed
        :closed
      when State::Merged
        :done
      when State::Open
        :open
      when State::Draft
        :muted
      when State::Queued
        :attention
      when nil
        :muted
      else
        T.absurd(@state)
      end
    end

    sig { returns(Symbol) }
    def primer_scheme
      case @state
      when State::Closed
        :closed
      when State::Merged
        :merged
      when State::Open
        :open
      when State::Draft
        :default
      when State::Queued
        :default # FIXME: Primer component needs a queued scheme
      when nil
        :default
      else
        T.absurd(@state)
      end
    end

    sig { returns(T.nilable(String)) }
    def octicon_name
      case @state
      when State::Merged
        "git-merge"
      when State::Open
        "git-pull-request"
      when State::Draft
        "git-pull-request-draft"
      when State::Queued
        "git-merge-queue"
      when State::Closed
        "git-pull-request-closed"
      when nil
        "git-pull-request"
      else
        T.absurd(@state)
      end
    end

    sig { returns(T.nilable(String)) }
    def state
      @state&.to_s
    end
  end
end
