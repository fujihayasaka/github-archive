# typed: strict
# frozen_string_literal: true

module TrackingBlocks
  class TasklistBlockAutocompleteResultComponent < ApplicationComponent
    extend T::Sig

    Hit = T.type_alias { T::Hash[Symbol, T.untyped] }
    ParamsForState = T.type_alias { T::Hash[Symbol, T.untyped] }

    sig { returns(T.nilable(Hit)) }
    attr_reader :hit

    sig { params(hit: Hit).void }
    def initialize(hit:)
      @hit = hit
    end

    sig { returns(T.nilable(ParamsForState)) }
    def octicon_params_for_state
      return unless enough_data?
      return not_planned if not_planned?
      return merged if merged?

      case state
      when :open then open
      when :closed then closed
      when :draft then draft
      else default
      end
    end

    sig { returns(T::Boolean) }
    def show_octicon_for_state?
      octicon_params_for_state.present?
    end

    private

    sig { returns(T::Boolean) }
    def not_planned?
      state_reason == :not_planned
    end

    sig { returns(T::Boolean) }
    def merged?
      state == :merged
    end

    sig { returns(T.nilable(Symbol)) }
    def state_reason
      T.must(hit)[:state_reason]&.to_sym
    end

    sig { returns(T.nilable(Symbol)) }
    def state
      T.must(hit)[:state]&.to_sym
    end

    sig { returns(T::Boolean) }
    def enough_data?
      state.present? || state_reason.present?
    end

    sig { returns(ParamsForState) }
    def open
      if pull_request?
        { name: :"git-pull-request", kwargs: { classes: "open" } }
      elsif issue?
        { name: :"issue-opened", kwargs: { classes: "open" } }
      else
        default
      end
    end

    sig { returns(ParamsForState) }
    def not_planned
      { name: :skip, kwargs: { color: :muted } }
    end

    sig { returns(ParamsForState) }
    def closed
      if pull_request?
        { name: :"git-pull-request-closed", kwargs: { classes: "closed" } }
      elsif issue?
        { name: :"issue-closed", kwargs: { classes: "closed" } }
      else
        default
      end
    end

    sig { returns(ParamsForState) }
    def merged
      { name: :"git-merge", kwargs: { classes: "merged" } }
    end

    sig { returns(ParamsForState) }
    def draft
      { name: :"git-pull-request-draft", kwargs: {} }
    end

    sig { returns(ParamsForState) }
    def default
      { name: :"plus-circle", kwargs: { color: :subtle } }
    end

    sig { returns(T::Boolean) }
    def pull_request?
      T.must(hit)[:type] == :pull_request
    end

    sig { returns(T::Boolean) }
    def issue?
      T.must(hit)[:type] == :issue
    end
  end
end
