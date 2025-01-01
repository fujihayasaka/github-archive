# typed: true
# frozen_string_literal: true
class Stafftools::Businesses::TrialsListComponent < ApplicationComponent
  attr_reader :active_trials, :expired_trials, :converted_trials, :cancelled_trials, :filter, :query, :tab

  def initialize(active_trials:, expired_trials:, converted_trials:, cancelled_trials:, filter:, query:, tab:)
    @active_trials = active_trials
    @expired_trials = expired_trials
    @converted_trials = converted_trials
    @cancelled_trials = cancelled_trials
    @filter = filter
    @query = query
    @tab = tab
  end

  def stafftools_active_trials_path
    trials_stafftools_enterprises_path + "?" + active_params
  end

  def stafftools_expired_trials_path
    trials_stafftools_enterprises_path + "?" + expired_params
  end

  def stafftools_converted_trials_path
    trials_stafftools_enterprises_path + "?" + converted_params
  end

  def stafftools_cancelled_trials_path
    trials_stafftools_enterprises_path + "?" + cancelled_params
  end

  private

  def active_params
    { tab: :active, query: query, filter: filter.except(:cancelled, :converted) }.to_query
  end

  def expired_params
    { tab: :expired, query: query, filter: filter.except(:cancelled, :converted) }.to_query
  end

  def converted_params
    { tab: :converted, query: query, filter: filter.except(:cancelled) }.to_query
  end

  def cancelled_params
    { tab: :cancelled, query: query, filter: filter.except(:converted) }.to_query
  end
end
