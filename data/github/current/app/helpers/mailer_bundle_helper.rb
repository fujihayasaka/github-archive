# typed: true
# frozen_string_literal: true

require "asset_bundles"

module MailerBundleHelper
  include ActionView::Helpers::TagHelper
  extend StaticAssetHelper

  # Creates a stylesheet tag for the primer-emails bundle.
  # We do this in a separate helper so we can avoid needing to load all of the normal Web specific helpers into Mailers.
  def primer_email_stylesheet_tag
    options = MailerBundleHelper.build_link_options
    tag(:link, options)
  end

  def self.build_link_options
    # since sorbet cannot find mailer_asset_host_url, we need to add T.bind(self, T.untyped) to disable type checking
    T.bind(self, T.untyped).mailer_asset_host_url
    options = {}
    options[:media] = "all"

    # mailer does not have access to `current_user`.
    asset_bundle = AssetBundles.new

    options[:rel] = "stylesheet"
    options[:href] = asset_bundle.bundle_url(
      "primer-emails.css",
      asset_host_url: mailer_asset_host_url,
    )

    options
  end

  def self.primer_email_stylesheet_uris
    # mailer does not have access to `current_user`.
    asset_bundles = AssetBundles.new
    filename = asset_bundles.expand_bundle_name("primer-emails.css")
    filepath = Rails.root.join("public/assets", filename)

    if File.exist?(filepath) && File.readable?(filepath)
      ["file:/#{filepath}"]
    else
      build_link_options[:href]
    end
  end
end
