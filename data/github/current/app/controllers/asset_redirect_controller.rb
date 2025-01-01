# typed: true
# frozen_string_literal: true

require "asset_bundles_helper"

class AssetRedirectController < ApplicationController
  # CAP is not required, this controller only redirects
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:index]

  def index
    assets = AssetBundlesHelper.new(current_user)
    bundle = "#{params[:name]}.#{params[:format]}"
    begin
      filename = assets.expand_bundle_name(bundle)
      redirect_to "#{GitHub.asset_host_url}/assets/#{filename}"
    rescue KeyError
      head :not_found, content_type: Mime[:text]
    end
  end
end
