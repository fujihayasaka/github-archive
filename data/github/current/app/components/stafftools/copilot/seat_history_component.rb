# typed: true
# frozen_string_literal: true

require "will_paginate/array"

class Stafftools::Copilot::SeatHistoryComponent < ApplicationComponent
  attr_reader :organization
  PER_PAGE = 10

  def initialize(organization)
    add_seat_history = Copilot::SeatHistory.where(organization: organization).group(:seat_created_at).count
    delete_seat_history = Copilot::SeatHistory.where(organization: organization).group(:seat_deleted_at).count
    seat_history = Hash.new
    add_seat_history.each do |key, value|
      if key.present?
        seat_history[key] = { added: value, deleted: 0 }
      end
    end

    delete_seat_history.each do |key, value|
      if seat_history[key].present?
        seat_history[key][:deleted] = value
      elsif key.present?
        seat_history[key] = { added: 0, deleted: value }
      end
    end

    @seat_history = seat_history.sort.reverse.to_h
  end

  def render?
    @seat_history.length > 0
  end

  def current_page
    (params[:seat_history_page] || 1).to_i
  end

  def total_pages
    (@seat_history.size.to_f / PER_PAGE).ceil
  end

  def paginated_history
    @seat_history.to_a.paginate(
      page: current_page,
      per_page: PER_PAGE
    )
  end
end
