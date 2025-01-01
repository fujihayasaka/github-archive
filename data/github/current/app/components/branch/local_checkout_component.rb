# typed: true
# frozen_string_literal: true

class Branch::LocalCheckoutComponent < ApplicationComponent

  def initialize(branch_name:)
    @branch_name = branch_name
  end

  def branch_name
    @branch_name
  end
end
