# typed: strict
# frozen_string_literal: true

module BundleHelper
  extend T::Helpers

  abstract!

  requires_ancestor { Kernel }
  requires_ancestor { ActionView::Helpers::TagHelper }
  requires_ancestor { ClientEnvHelper }

  sig { abstract.returns(T::Boolean) }
  def logged_in?; end

  sig { returns(AssetBundles) }
  def asset_bundle
    @asset_bundle ||= T.let(AssetBundles.new, T.nilable(AssetBundles))
  end

  # Set lazy: true to delay loading the stylesheet until later.
  sig { params(source: T.any(String, Symbol), lazy: T::Boolean, tag_options: T::Hash[T.any(String, Symbol), T.untyped]).returns(ActiveSupport::SafeBuffer) }
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

  # Creates all necessary script tags for a unexpanded bundle.
  #
  # @param source [String] The unexpanded bundle name.
  #
  # @return [String] The <script> tags.
  sig { params(source: T.any(String, Symbol), test_selector: T.nilable(String)).returns(ActiveSupport::SafeBuffer) }
  def javascript_bundle(source, test_selector: nil)
    @added_bundles = T.let(nil, T.nilable(T::Array[T::Hash[String, T.untyped]])) unless defined?(@added_bundles)
    @added_bundles = [] if @added_bundles.nil?

    # Don't add bundles that are loaded by `controller_javascript_bundles`.
    bundles = asset_bundle.expand_bundle_files(suffix_with(source, "js")) - expanded_required_bundles - @added_bundles

    script_tags = bundles.map do |bundle|
      javascript_bundle_tag(bundle, test_selector: test_selector)
    end

    if FeatureFlag.vexi.enabled_or_raise?(:bundles_keep_css_modules) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      # Keep track of the bundles which are already on the page
      # Don't track css bundles as they can be removed from the page if the partial containing them is removed,
      # so we want to force them inline anywhere they are needed
      @added_bundles.concat(bundles.reject { |bundle| bundle[:css_src] })
    else
      @added_bundles.concat(bundles)
    end

    safe_join(script_tags, "\n")
  end

  sig { params(source: T.any(String, Symbol), test_selector: T.untyped).returns(T.untyped) }
  def javascript_preload_tag(source, test_selector: nil)
    bundles = asset_bundle.expand_bundle_files(suffix_with(source, "js"))

    link_tags = bundles.map do |bundle|

      options = { crossorigin: GitHub.asset_crossorigin_with_credentials? ? "use-credentials" : "anonymous" }
      options[:rel] = "preload"
      options[:as] = "script"
      options[:href] = asset_bundle.bundle_url(bundle[:src], expand: false)

      tag(:link, options)
    end

    safe_join(link_tags, "\n")
  end

  # Creates a <script> tag for the given source.
  #
  # @param source [String] The expanded bundle name.
  # @param test_selector [String] The value of a `data-test-selector` attribute
  #   that will be added to the script tag (Optional).
  #
  # @return [String] The <script> tag.
  sig { params(source: T.any(String, Symbol), test_selector: T.nilable(String), blocking: T::Boolean).returns(T.nilable(ActiveSupport::SafeBuffer)) }
  def javascript_tag(source, test_selector: nil, blocking: false)
    # Don't render if the bundle has already been loaded
    return if page_javascript_bundles.include?(source)

    page_javascript_bundles << source

    options = {
      crossorigin: GitHub.asset_crossorigin_with_credentials? ? "use-credentials" : "anonymous",
      type: GitHub.vite_dev_server_enabled? ? "module" : "application/javascript",
      src: asset_bundle.bundle_url(source, expand: false)
    }

    options["data-test-selector"] = test_selector if test_selector.present?

    options["defer"] = true unless blocking

    content_tag(:script, "", options)
  end

  # Returns an Array<String> of bundle file names to include as `<link>` tags.
  sig { returns(T::Set[String]) }
  def stylesheet_required_bundles
    @stylesheet_required_bundles = T.let(nil, T.nilable(T::Set[String])) unless defined?(@stylesheet_required_bundles)
    return @stylesheet_required_bundles unless @stylesheet_required_bundles.nil?

    bundles = asset_bundle.required_stylesheet_bundles
    bundles << "staff" if respond_to?(:staff_assets?) && T.unsafe(self).staff_assets?
    bundles << "devtools" if respond_to?(:devtools_assets?) && T.unsafe(self).devtools_assets?
    @stylesheet_required_bundles = bundles.to_set
  end

  sig { returns(ActiveSupport::SafeBuffer) }
  def controller_stylesheet_bundles
    safe_join(T.unsafe(self).stylesheet_bundles.map { |source| stylesheet_bundle(source) }, "\n")
  end

  # Generates all script tags needed for the current page.
  sig { params(skip_client_env: T::Boolean).returns(ActiveSupport::SafeBuffer) }
  def controller_javascript_bundles(skip_client_env: false)
    bundle_tags = expanded_required_bundles.map { |bundle| javascript_bundle_tag(bundle) }

    # insert client config script before other JS tags so that config is always available to JS
    bundle_tags.unshift client_env_script_tag unless skip_client_env

    safe_join(bundle_tags, "\n")
  end

  private

  # Creates either a <script> tag if the bundle loads JS or a <link> tag if the bundle loads CSS
  sig { params(bundle: T::Hash[Symbol, T.untyped], test_selector: T.nilable(String)).returns(T.nilable(ActiveSupport::SafeBuffer)) }
  def javascript_bundle_tag(bundle, test_selector: nil)
    if bundle[:css_src]
      module_stylesheet_tag(bundle[:css_src])
    else
      javascript_tag(bundle[:src], test_selector: test_selector, blocking: bundle[:blocking] == true)
    end
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
  sig { returns(T::Set[String]) }
  def javascript_required_bundles
    @javascript_required_bundles = T.let(nil, T.nilable(T::Set[String])) unless defined?(@javascript_required_bundles)
    return @javascript_required_bundles unless @javascript_required_bundles.nil?

    bundles = logged_in? ? [] : ["high-contrast-cookie"]
    bundles += asset_bundle.required_bundles
    bundles += ["features"] if T.unsafe(self).datafile_features&.present?
    bundles += ["staff"] if respond_to?(:staff_assets?) && T.unsafe(self).staff_assets?
    @javascript_required_bundles = bundles.to_set
  end

  sig { params(source: T.any(String, Symbol)).returns(ActiveSupport::SafeBuffer) }
  def module_stylesheet_tag(source)
    options = { crossorigin: GitHub.asset_crossorigin_with_credentials? ? "use-credentials" : "anonymous" }
    options[:media] = "all"
    options[:rel] = "stylesheet"

    href = asset_bundle.bundle_url(source, expand: false)

    options[:href] = href

    tag(:link, options)
  end

  # Returns a Set with all the loaded bundles in the page.
  sig { returns(T::Set[T.any(String, Symbol)]) }
  def page_javascript_bundles
    @page_javascript_bundles = T.let(nil, T.nilable(T::Set[T.any(String, Symbol)])) unless defined?(@page_javascript_bundles)
    return @page_javascript_bundles unless @page_javascript_bundles.nil?
    @page_javascript_bundles = Set.new
  end

  # Returns a Set of all the required files to load a page.
  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def expanded_required_bundles
    @expanded_required_bundles = T.let(nil, T.nilable(T::Array[T::Hash[Symbol, T.untyped]])) unless defined?(@expanded_required_bundles)
    return @expanded_required_bundles unless @expanded_required_bundles.nil?

    bundles = javascript_required_bundles
    bundles += T.unsafe(self).javascript_bundles if respond_to?(:javascript_bundles)

    @expanded_required_bundles = bundles.map { |source| suffix_with(source, "js") }
                                        .map { |source| asset_bundle.expand_bundle_files(source) }
                                        .flatten
                                        .uniq { |bundle| bundle[:src] || bundle[:css_src] }
  end

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def expanded_required_stylesheets
    @expanded_required_stylesheets = T.let(nil, T.nilable(T::Array[T::Hash[Symbol, T.untyped]])) unless defined?(@expanded_required_stylesheets)
    return @expanded_required_stylesheets unless @expanded_required_stylesheets.nil?

    bundles = stylesheet_required_bundles
    bundles += T.unsafe(self).stylesheet_bundles if respond_to?(:stylesheet_bundles)

    @expanded_required_stylesheets = bundles.map { |source| suffix_with(source, "css") }
                                        .map { |source| asset_bundle.expand_bundle_files(source) }
                                        .flatten
                                        .uniq { |bundle| bundle[:src] }
  end

  sig { params(source: T.any(String, Symbol), suffix: String).returns(String) }
  def suffix_with(source, suffix)
    source.to_s.ends_with?(".#{suffix}") ? source.to_s : "#{source}.#{suffix}"
  end
end
