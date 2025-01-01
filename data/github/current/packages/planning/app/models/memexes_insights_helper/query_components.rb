# typed: true
# frozen_string_literal: true

module MemexesInsightsHelper
  class QueryComponents
    attr_accessor :select_q, :join_q, :where_q, :group_q, :order_q

    def initialize(memex_org, date_selector)
      @select_q = ["P.Date"]
      @join_q = []
      @where_q = ["P.ProjectId = #{memex_org.id}", "P.DateKey #{date_selector}"].select(&:present?)
      @group_q = ["P.Date"]
      @order_q = []
    end
  end
end
