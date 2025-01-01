# frozen_string_literal: true

require "test_helper"

class EagerLoadingTest < ActiveSupport::TestCase
  # We eager load all application classes in production, which can sometimes
  # uncover references to classes or modules for which Rails can't find the
  # definition. Let's uncover those problems here instead!
  test "Rails.application.eager_load! succeeds" do
    assert_nothing_raised do
      Rails.application.eager_load!
    end
  end
end
