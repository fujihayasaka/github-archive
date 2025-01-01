# typed: false
# frozen_string_literal: true

module Stafftools::Billing
  module TestMeteredProductsHelper
    def options_for_emission_source(source = nil)
      user = ["User: #{current_user.login}", "User_#{current_user.id}"]
      orgs = current_user.organizations.map { |org| ["Organization: #{org.login}", "Org_#{org.id}"] }
      enterprises = current_user.businesses.map { |enterprise| ["Enterprise: #{enterprise.name}", "Enterprise_#{enterprise.id}"] }
      potential_sources = [user] + orgs + enterprises
      options_for_select(potential_sources.compact, source)
    end
  end
end
