# typed: true
# frozen_string_literal: true

module Discussions
  class TopSearchComponent < ApplicationComponent
    extend T::Sig
    include HydroHelper

    # org_param - the display_login of the Organization to use in routing, if working with org-level discussions
    sig do
      params(
        current_repository: T.untyped,
        parsed_discussions_query: T.untyped,
        query: T.untyped,
        org_param: T.nilable(String)
      ).void
    end
    def initialize(current_repository: nil, parsed_discussions_query: nil, query: nil, org_param: nil)
      @current_repository = current_repository
      @parsed_discussions_query = parsed_discussions_query
      @query = query
      @org_param = org_param
    end

    attr_reader :current_repository, :parsed_discussions_query, :query

    sig { returns T.nilable(String) }
    attr_reader :org_param

    memoize def menu_items_list
      begin
        today = Date.today.strftime("%F")
        beginning_of_yesterday = (Date.today - 1.day).strftime("%F")
        beginning_of_week = (Date.today - 7.days).strftime("%F")
        beginning_of_month = (Date.today - 30.days).strftime("%F")
        beginning_of_year = (Date.today - 365.days).strftime("%F")

        [
          { created_date: today, type: "Sort by:", text: "Latest activity", target: "ALL" },
          { created_date: nil, type: "Sort by:", text: "Date created", target: "BEGINNING" },
          { created_date: beginning_of_yesterday, type: "Top:", text: "Top: Past day", target: "PAST_DAY" },
          { created_date: beginning_of_week, type: "Top:", text: "Top: Past week", target: "PAST_WEEK" },
          { created_date: beginning_of_month, type: "Top:", text: "Top: Past month", target: "PAST_MONTH" },
          { created_date: beginning_of_year, type: "Top:", text: "Top: Past year", target: "PAST_YEAR" },
          { created_date: nil, type: "Top:", text: "Top: All", target: "ALL" }
        ]
      end
    end

    def search_path(created_date:, text:)
      if text == "Latest activity"
        return helpers.discussions_search_path(
          discussions_query: parsed_discussions_query,
          replace: { sort: nil, created: nil },
          org_param: org_param,
        )
      end
      if text == "Date created"
        return helpers.discussions_search_path(
          discussions_query: parsed_discussions_query,
          replace: { sort: "date_created", created: nil },
          org_param: org_param,
        )
      end
      if created_date
        return helpers.discussions_search_path(
          discussions_query: parsed_discussions_query,
          replace: { sort: "top" },
          created_override: ">=#{created_date}",
          org_param: org_param,
        )
      end
      helpers.discussions_search_path(
        discussions_query: parsed_discussions_query,
        replace: { sort: "top", created: nil },
        org_param: org_param,
      )
    end

    def selected?
      query.include?("sort:top")
    end

    def selected_menu_item
      return menu_items_list[1] if query.include?("date_created")
      return menu_items_list.first if query.blank? || !query.include?("sort")
      menu_items_list.find { |item| item[:created_date] && query.include?(item[:created_date]) } || menu_items_list.last
    end

    def selected_menu_item_text
      selected_menu_item[:text].split(": ").last
    end
  end
end
