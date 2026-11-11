# frozen_string_literal: true

require "rails_helper"

RSpec.describe Aqueduct do
  it "configures the same queues in aqueduct_enterprise.rb and aqueduct_worker.rb + aqueduct_throttled_worker.rb" do
    # On dotcom we configure queues in aqueduct_worker.rb and aqueduct_throttled_worker.rb, on GHES they all go in
    # aqueduct_enterprise.rb, this tests to ensure that all queues are configured in both environments
    enterprise_queues = File.read(
      Rails.root.join("config/resqued/aqueduct_enterprise.rb")
    ).scan(/queue "(.*?)"/).flatten

    production_queues = File.read(
      Rails.root.join("config/resqued/aqueduct_worker.rb")
    ).scan(/queue "(.*?)"/).flatten
    throttled_production_queues = File.read(
      Rails.root.join("config/resqued/aqueduct_throttled_worker.rb")
    ).scan(/queue "(.*?)"/).flatten

    expect(enterprise_queues).to match_array(production_queues + throttled_production_queues)
  end
end
