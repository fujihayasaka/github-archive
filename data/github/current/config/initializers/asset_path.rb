# typed: true
# frozen_string_literal: true

# configure asset path rewriting in staging and production environments
ActionController::Base.asset_host = GitHub.static_asset_host_url

# Disable ?123 asset query strings.
# Sprockets fingerprints pretty much handles this for us
ENV["RAILS_ASSET_ID"] = ""
