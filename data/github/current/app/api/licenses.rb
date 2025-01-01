# typed: true
# frozen_string_literal: true

require "will_paginate/array"

class Api::Licenses < Api::App

  def find_license!
    license = License.find_by_key(params[:key], hidden: true, psuedo: false)
    record_or_404(license)
  end

  get "/licenses", operation_id: "licenses/get-all-commonly-used" do
    @route_owner = Platform::NoOwnerBecause::UNAUDITED
    control_access :public_site_information, resource: Platform::PublicResource.new, allow_integrations: true, allow_user_via_granular_actor: true # rubocop:disable GitHub/PublicResource

    featured = params[:featured].present? ? parse_bool(params[:featured]) : nil
    licenses = License.all(featured: featured)
    deliver :license_hash, licenses.paginate(pagination), status: 200
  end

  get "/licenses/:key", operation_id: "licenses/get" do
    @route_owner = Platform::NoOwnerBecause::UNAUDITED
    control_access :public_site_information, resource: Platform::PublicResource.new, allow_integrations: true, allow_user_via_granular_actor: true # rubocop:disable GitHub/PublicResource

    deliver :license_hash, find_license!,
      full: true
  end
end
