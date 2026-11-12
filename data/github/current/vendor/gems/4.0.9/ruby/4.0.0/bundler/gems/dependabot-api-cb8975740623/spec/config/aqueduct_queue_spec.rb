# frozen_string_literal: true

require "rails_helper"

RSpec.describe Aqueduct do
  it "configures the same queues in aqueduct_enterprise.rb as production queues" do
    # On dotcom we configure queues in aqueduct_worker.rb, aqueduct_throttled_worker.rb, and aqueduct_graph_worker.rb,
    # but on GHES they all go in aqueduct_enterprise.rb, this tests to ensure that all queues are configured correctly.
    enterprise_queues = File.read(
      Rails.root.join("config/resqued/aqueduct_enterprise.rb")
    ).scan(/queue "(.*?)"/).flatten

    production_queues = File.read(
      Rails.root.join("config/resqued/aqueduct_worker.rb")
    ).scan(/queue "(.*?)"/).flatten
    throttled_production_queues = File.read(
      Rails.root.join("config/resqued/aqueduct_throttled_worker.rb")
    ).scan(/queue "(.*?)"/).flatten
    graph_production_queues = File.read(
      Rails.root.join("config/resqued/aqueduct_graph_worker.rb")
    ).scan(/queue "(.*?)"/).flatten

    expect(enterprise_queues).to match_array(production_queues + throttled_production_queues + graph_production_queues)
  end
end
