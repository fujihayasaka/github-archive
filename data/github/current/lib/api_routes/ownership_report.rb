# typed: true
# frozen_string_literal: true
require "csv"

class ApiRoutes::OwnershipReport < ApiRoutes::DefaultReport
  def print
    output = [%w(service_mapping method route)]

    collections.each do |collection|
      endpoints = collection.endpoints.map do |endpoint|
        output << [endpoint.service_mapping, endpoint.verb, endpoint.route]
      end
    end

    csv = CSV.new($stdout)
    output.map { |row| csv << row }
  end
end
