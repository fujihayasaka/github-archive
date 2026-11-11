# typed: true
# frozen_string_literal: true

class DashboardNotice
  attr_reader :name

  def initialize(notice_name)
    @name = notice_name
  end

  def to_s
    name
  end
end
