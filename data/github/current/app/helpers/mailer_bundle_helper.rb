# typed: false
# frozen_string_literal: true
require "asset_bundles"

module MailerBundleHelper
  extend StaticAssetHelper

  # Creates a stylesheet tag for the primer-emails bundle.
  # We do this in a separate helper so we can avoid needing to load all of the normal Web specific helpers into Mailers.
  def primer_email_stylesheet_tag
    options = MailerBundleHelper.build_link_options
    tag(:link, options)
  end

  def self.build_link_options
    options = {}
    options[:media] = "all"

    # mailer does not have access to `current_user`.
    asset_bundle = AssetBundlesHelper.new

    options[:rel] = "stylesheet"
    options[:href] = asset_bundle.bundle_url(
      "primer-emails.css",
      asset_host_url: mailer_asset_host_url,
    )

    options
  end

  def self.primer_email_stylesheet_uris
    # mailer does not have access to `current_user`.
    asset_bundles = AssetBundlesHelper.new
    filename = asset_bundles.expand_bundle_name("primer-emails.css")
    filepath = Rails.root.join("public/assets", filename)

    if File.exist?(filepath) && File.readable?(filepath)
      ["file:/#{filepath}"]
    else
      build_link_options[:href]
    end
  end
end
