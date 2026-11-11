# typed: true
# frozen_string_literal: true

class Statuses::ContextsHelper

  # Public: Initialize a combined status contexts helper
  #
  # contexts_with_state - An Array of Arrays consisting of two elements:
  #                       [<context_name>, <context_state>]
  def initialize(contexts_with_state)
    @contexts_with_state = contexts_with_state
  end

  # Public: Are all contexts succeeding?
  #
  # Returns Boolean
  def all_succeeded?
    total_count == (state_counts["SUCCESS"].to_i + state_counts["NEUTRAL"].to_i + state_counts["SKIPPED"].to_i)
  end

  # Public: Are all contexts failing?
  #
  # Returns Boolean
  def all_failing?
    total_count == (state_counts["FAILURE"].to_i + state_counts["ERROR"].to_i)
  end

  # Public: Summary text with counts of each context state
  #
  #   "1 failing, 5 pending, 5 errored, and 5 successful checks"
  #
  # Returns String
  def summary_text
    return @summary_text if defined?(@summary_text)

    counts_with_state = state_counts.map do |state, count|
      "#{count} #{StatusCheckConfig.adjective_state(state)}"
    end
    @summary_text = "#{counts_with_state.to_sentence} check".pluralize(total_count)
  end

  # Public: Short text with counts of successful vs failing
  #
  #   "2 / 5 checks OK"
  #
  # Returns String
  def short_text
    successful_count = state_counts["SUCCESS"].to_i
    "#{successful_count} / #{total_count} checks OK"
  end

  # Public: Counts contexts by their state
  #
  # Returns Hash with state as keys and counts as values
  def state_counts
    return @state_counts if defined?(@state_counts)

    @state_counts = contexts_with_state
      .group_by { |_context, state| state }
      .map do |state, contexts|
        [state, contexts.count]
      end.to_h
  end

  private

  attr_reader :contexts_with_state

  def total_count
    contexts_with_state.size
  end

end
