# typed: true
# frozen_string_literal: true
require "asset_bundles_helper"

module BundleHelper
  include ClientEnvHelper
  include FeatureFlagHelper
  include Kernel

  def asset_bundle
    # BundleHelper can be used by other helpers that don't have access to `current_user`, like MailerBundlerHelper
    # and ViewComponent previews.
    @asset_bundle ||= respond_to?(:current_user) ? AssetBundlesHelper.new(T.unsafe(self).current_user) : AssetBundlesHelper.new
  end

  # Creates all necessary script tags for a unexpanded bundle.
  #
  # @param source [String] The unexpanded bundle name.
  #
  # @return [String] The <script> tags.
  def javascript_bundle(source, test_selector: nil)
    @added_bundles = [] unless defined?(@added_bundles)

    # Don't add bundles that are loaded by `controller_javascript_bundles`.
    bundles = asset_bundle.expand_bundle_files(suffix_with(source, "js")) - expanded_required_bundles - @added_bundles

    script_tags = bundles.map do |bundle|
      javascript_bundle_tag(bundle, test_selector: test_selector)
    end

    @added_bundles.concat(bundles)

    safe_join(script_tags, "\n")
  end

  # Creates either a <script> tag if the bundle loads JS or a <link> tag if the bundle loads CSS
  def javascript_bundle_tag(bundle, test_selector: nil)
    if bundle[:css_src]
      module_stylesheet_tag(bundle[:css_src])
    else
      javascript_tag(bundle[:src], test_selector: test_selector)
    end
  end

  # Creates a <script> tag for the given source.
  #
  # @param source [String] The expanded bundle name.
  # @param test_selector [String] The value of a `data-test-selector` attribute
  #   that will be added to the script tag (Optional).
  #
  # @return [String] The <script> tag.
  def javascript_tag(source, test_selector: nil)
    # Don't render if the bundle has already been loaded
    return if page_javascript_bundles.include?(source)

    page_javascript_bundles << source

    options = {
      crossorigin: GitHub.asset_crossorigin_with_credentials? ? "use-credentials" : "anonymous",
      defer: true,
      type: "application/javascript"
    }

    url = asset_bundle.bundle_url(source, expand: false)

    options[:type] = "application/javascript"
    options["data-test-selector"] = test_selector if test_selector.present?
    options[:src] = url

    content_tag(:script, "", options)
  end

  # A chunk is a file created by Rollup during compilation that contains
  # module code referenced by multiple bundles. The goal is to download and
  # cache code only once regardless of how many bundles depend on it. As we
  # navigate the site, the chunks needed for those pages are downloaded and
  # executed as needed. We're never loading the full product code on any
  # page.
  #
  # Each bundle declares a dependency on the chunk file and import it so it
  # has access to the exported functions within the chunk. Rollup rewrites
  # imports for us depending on where the source module ends up in the
  # compiled output. The real output uses a System loader, but fundamentally
  # it's doing this:
  #
  # `import {fetch} from './fetch'` -> `import {f} from 'chunk-deadbeef.js'`
  #
  # Rollup determines which modules belong in which chunks and wires the
  # exports and imports together. The app is responsible for downloading
  # the chunk files when they are needed. We could choose to download all
  # chunks on every page, but that defeats the goal of loading only the
  # code required on each page.
  #
  # We do the following:
  #
  # - Render one *inert* script element per chunk file in the HTML document:
  #   `<script src="" data-src="chunk-1.js">`.
  # - Use system-lite.js to activate those scripts by moving the `data-src`
  #   attribute to `src`. The browser then downloads and executes the JS file.
  #   That chunk file contains calls to `System.register()` to add its exported modules
  #   to the registry. That resolves any other Promise waiting to import those
  #   functions.
  #
  # Returns an Array<String> of bundle file names to include as `<script>` tags.
  def javascript_required_bundles
    return @javascript_required_bundles if defined?(@javascript_required_bundles)

    bundles = asset_bundle.required_bundles
    bundles += ["features"] if T.unsafe(self).datafile_features&.present?
    bundles += ["staff"] if respond_to?(:staff_assets?) && T.unsafe(self).staff_assets?
    @javascript_required_bundles = bundles.to_set
  end

  def module_stylesheet_tag(source)
    options = { crossorigin: GitHub.asset_crossorigin_with_credentials? ? "use-credentials" : "anonymous" }
    options[:media] = "all"
    options[:rel] = "stylesheet"

    href = asset_bundle.bundle_url(source, expand: false)

    options[:href] = href

    tag(:link, options)
  end

  # Set lazy: true to delay loading the stylesheet until later.
  def stylesheet_bundle(source, lazy: false, tag_options: {})
    dev_script = if GitHub.webpack_dev_server_enabled?
      # When using webpack dev server with css, we need to include a js file per css file to handle hot module replacement.
      javascript_bundle("#{source}.css")
    else
      ""
    end

    options = { crossorigin: GitHub.asset_crossorigin_with_credentials? ? "use-credentials" : "anonymous" }
    options[:media] = "all"

    options[:rel] = "stylesheet"

    href = asset_bundle.bundle_url("#{source}.css")
    if lazy
      options["data-href"] = href
    else
      options[:href] = href
    end

    tag(:link, tag_options.merge(options)) << dev_script
  end

  # Returns an Array<String> of bundle file names to include as `<link>` tags.
  def stylesheet_required_bundles
    return @stylesheet_required_bundles if defined?(@stylesheet_required_bundles)

    bundles = %w[primer-primitives primer global github]
    bundles << "staff" if respond_to?(:staff_assets?) && T.unsafe(self).staff_assets?
    bundles << "devtools" if respond_to?(:devtools_assets?) && T.unsafe(self).devtools_assets?
    bundles << "development" if Rails.env.development?
    @stylesheet_required_bundles = bundles.to_set
  end

  # Returns a Set with all the loaded bundles in the page.
  def page_javascript_bundles
    @page_javascript_bundles ||= Set.new
  end

  def controller_stylesheet_bundles
    safe_join(T.unsafe(self).stylesheet_bundles.map { |source| stylesheet_bundle(source) }, "\n")
  end

  # Generates all script tags needed for the current page.
  def controller_javascript_bundles
    bundle_tags = expanded_required_bundles.map { |bundle| javascript_bundle_tag(bundle) }

    # insert client config script before other JS tags so that config is always available to JS
    bundle_tags.unshift client_env_script_tag

    safe_join(bundle_tags, "\n")
  end

  # Returns a Set of all the required files to load a page.
  def expanded_required_bundles
    return @expanded_required_bundles if defined?(@expanded_required_bundles)

    bundles = javascript_required_bundles
    bundles += T.unsafe(self).javascript_bundles if respond_to?(:javascript_bundles)

    @expanded_required_bundles = bundles.map { |source| suffix_with(source, "js") }
                                        .map { |source| asset_bundle.expand_bundle_files(source) }
                                        .flatten
                                        .uniq { |bundle| bundle[:src] || bundle[:css_src] }
  end

  def expanded_required_stylesheets
    return @expanded_required_stylesheets if defined?(@expanded_required_stylesheets)

    bundles = stylesheet_required_bundles
    bundles += T.unsafe(self).stylesheet_bundles if respond_to?(:stylesheet_bundles)

    @expanded_required_stylesheets = bundles.map { |source| suffix_with(source, "css") }
                                        .map { |source| asset_bundle.expand_bundle_files(source) }
                                        .flatten
                                        .uniq { |bundle| bundle[:src] }
  end

  def suffix_with(source, suffix)
    source.to_s.ends_with?(".#{suffix}") ? source : "#{source}.#{suffix}"
  end
end
