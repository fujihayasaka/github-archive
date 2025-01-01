# typed: true
# frozen_string_literal: true

class MergeQueues::EntryStatus::DetailComponent < ApplicationComponent
  include StatusHelper
  include AvatarHelper
  include ApplicationLogoHelper

  attr_reader :summary_color, :summary, :details, :test_selector_prefix, :check_runs_list

  def initialize(summary_color: :default, summary:, details:, test_selector_prefix:, check_runs_list: [])
    @summary_color = summary_color
    @summary = summary
    @details = details
    @test_selector_prefix = test_selector_prefix
    @check_runs_list = check_runs_list
  end

  memoize def sorted_check_runs_list
    begin
      # 'true' comes after 'false' in lexical sort order, but we want to show
      # things that evaluate to 'true' first. hopefully variables make this clearer
      first = 0
      second = 1
      check_runs_list.sort_by do |check_run|
        [
          StatusCheckConfig::FAILURE_STATES.include?(check_run.state) ? first : second,
          StatusCheckConfig::PENDING_STATES.include?(check_run.state) ? first : second,
          StatusCheckConfig::INCOMPLETE_STATES.include?(check_run.state) ? first : second,
          StatusCheckConfig::SUCCESS_STATES.include?(check_run.state) ? first : second,
        ]
      end
    end
  end
end
