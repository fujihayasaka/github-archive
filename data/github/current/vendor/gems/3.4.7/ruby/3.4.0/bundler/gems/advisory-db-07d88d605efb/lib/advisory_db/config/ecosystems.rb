# frozen_string_literal: true

module AdvisoryDB
  module Config
    # Dictionary of recognized ecosystems
    #
    # Be sure to also check AdvisoryDBToolkit's ECOSYSTEM_OSV_MAP hash if you
    # are adding or removing ecosystems here.
    module Ecosystems
      # Ecosystems that are recognized and available in the inbox, curatable or
      # not, and publishable or not. As more ecosystems are supported, they
      # must be added to the list below. All other lists below are expected to
      # be a subset of this.
      #
      # Ecosystem name requirements:
      # - max length of an ecosystem name is 20 characters due to database
      #   field length restrictions
      # - min length of an ecosystem name is 2 characters (arbitrarily chosen)
      # - characters restricted to alphanumeric and underscore due to GraphQL
      #   name validation
      # - must start with a letter
      #
      # Order is not important, so please keep alphabetized.
      ECOSYSTEMS = %w[
        actions
        composer
        erlang
        go
        maven
        npm
        nuget
        other
        pip
        pub
        rubygems
        rust
        swift
      ].freeze
      private_constant :ECOSYSTEMS

      # TEMPORARY: PURL type ecosystems. These are kept separate from
      # ECOSYSTEMS so that we can use a feature flag to control rollout, but
      # they can eventually be combined.
      PURL_TYPE_ECOSYSTEMS = %w[
        alpm
        apk
        bitbucket_repository
        cocoapods
        conan_center
        conda_forge
        cran
        deb
        docker_hub
        generic
        github_repository
        hackage
        huggingface
        mlflow
        qpkg
        oci
        rpm
        swid
      ].freeze

      # The subset of ECOSYSTEMS that are available in the inbox for curators
      # to select, whether publishable or not.
      #
      # The order here is the order they are displayed in select lists, so
      # prefer alphabetical unless there's a good reason not to.
      CURATED_ECOSYSTEMS = %w[
        actions
        composer
        erlang
        go
        maven
        npm
        nuget
        other
        pip
        pub
        rubygems
        rust
        swift
      ].freeze
      private_constant :CURATED_ECOSYSTEMS

      # The subset of CURATED_ECOSYSTEMS that are supported by dotcom and
      # publishable by curators. Ecosystems that are not in this list can be
      # saved and updated in the inbox but not published.
      #
      # Order is not important, so please keep alphabetized.
      CURATOR_PUBLISHABLE_ECOSYSTEMS = %w[
        actions
        composer
        erlang
        go
        maven
        npm
        nuget
        other
        pip
        pub
        rubygems
        rust
        swift
      ].freeze
      private_constant :CURATOR_PUBLISHABLE_ECOSYSTEMS

      # A map of CURATED_ECOSYSTEMS to user-friendly labels. Any ecosystem not
      # in this list will use the ecosystem name as its label. See
      # `ecosystem_label` below.
      #
      # Order is not important, so please keep alphabetized.
      ECOSYSTEM_LABELS = {
        "actions" => "GitHub Actions",
        "composer" => "Composer",
        "erlang" => "Erlang",
        "go" => "Go",
        "maven" => "Maven",
        "npm" => "npm",
        "nuget" => "NuGet",
        "other" => "Other",
        "pip" => "pip",
        "pub" => "Pub.dev",
        "rubygems" => "RubyGems",
        "rust" => "Rust",
        "swift" => "Swift",
      }.freeze

      # A map of CURATED_ECOSYSTEMS to UI colors. Any ecosystem not in this
      # list will use the fallback color. See `ecosystem_color` below.
      #
      # Order is not important, so please keep alphabetized.
      ECOSYSTEM_COLORS = {
        "actions" => "0366D6",
        "composer" => "f28d1a",
        "erlang" => "b83998",
        "go" => "00add8",
        "maven" => "b07219",
        "npm" => "f1e05a",
        "nuget" => "2b9cdf",
        "other" => "000",
        "pip" => "3572a5",
        "pub" => "00B4AB",
        "rubygems" => "701516",
        "rust" => "dea584",
        "swift" => "df5e3d",
      }.freeze

      # A map of CURATED_ECOSYSTEMS to Dependency Graph's GraphQL API ecosystem
      # slugs. A nil value means the ecosystem is not supported by Dependency
      # Graph.
      #
      # See https://github.com/github/dependency-graph-api/blob/master/app/models/types.rb.
      #
      # Order is not important, so please keep alphabetized.
      ECOSYSTEM_DEPENDENCY_GRAPH_MAP = {
        "actions" => :ACTIONS,
        "composer" => :COMPOSER,
        "erlang" => nil,
        "go" => :GO,
        "maven" => :MAVEN,
        "npm" => :NPM,
        "nuget" => :NUGET,
        "other" => nil,
        "pip" => :PIP,
        "pub" => nil,
        "rubygems" => :RUBYGEMS,
        "rust" => :RUST,
        "swift" => :SWIFT,
      }.freeze

      AI_PREDICTION_RESULTS_ECOSYSTEMS_MAP = {
        "GitHub Actions" => "actions",
        "Composer" => "composer",
        "Erlang" => "erlang",
        "Go" => "go",
        "Maven" => "maven",
        "npm" => "npm",
        "NuGet" => "nuget",
        "Other" => "other",
        "pip" => "pip",
        "Pub.dev" => "pub",
        "RubyGems" => "rubygems",
        "Rust" => "rust",
        "Swift" => "swift",
      }.freeze

      PROMPT_ECOSYSTEMS = %w[
        actions
        composer
        erlang
        go
        maven
        npm
        nuget
        pip
        pub
        rubygems
        rust
        swift
      ].freeze

      PROMPT_PACKAGE_FORMAT_EXAMPLES = {
        "GitHub Actions" => "kartverket/github-workflows",
        "Composer" => "miniorange/miniorange-saml",
        "Erlang" => "rabbit_common",
        "Go" => "github.com/goharbor/harbor",
        "Maven" => "org.opennms:opennms-webapp",
        "npm" => "seco-leveldown",
        "NuGet" => "Microsoft.NETCore.AppMicrosoft.NETCore.App",
        "pip" => "django-filter",
        "Pub.dev" => "personnummer",
        "RubyGems" => "twitter-bootstrap-rails",
        "Rust" => "rust-embedrust-embed",
        "Swift" => "https://github.com/migueldeicaza/SwiftTerm",
      }.freeze

      # All recognized ecosystems
      def ecosystems
        unless defined?(@ecosystems) && !Rails.env.test?
          @ecosystems = ECOSYSTEMS

          if include_purl_type_ecosystems?
            @ecosystems += PURL_TYPE_ECOSYSTEMS
          end
        end
        @ecosystems
      end

      # Ecosystems that are recognized in the inbox and selectable by curators
      def curated_ecosystems
        CURATED_ECOSYSTEMS
      end

      # Ecosystems that are supported in dotcom and can be published by curators
      def curator_publishable_ecosystems
        CURATOR_PUBLISHABLE_ECOSYSTEMS
      end

      # Ecosystems that are supported in dotcom but are not curatable.
      # Ecosystems in this list can be auto-published.
      def auto_publishable_ecosystems
        ecosystems - curated_ecosystems
      end

      # Ecosystems that are supported in dotcom and therefore publishable,
      # whether curatable or not.
      def publishable_ecosystems
        curator_publishable_ecosystems + auto_publishable_ecosystems
      end

      def ecosystem_label(ecosystem)
        ECOSYSTEM_LABELS.fetch(ecosystem) { ecosystem.titleize }
      end

      def ai_prediction_result_to_ecosystem(result)
        AI_PREDICTION_RESULTS_ECOSYSTEMS_MAP.fetch(result)
      end

      def ecosystem_color(ecosystem)
        # The fallback is Primer's `fg.muted`
        # See: https://primer.style/design/foundations/color#foregrounds
        ECOSYSTEM_COLORS[ecosystem] || "59606a"
      end

      def dependency_graph_ecosystem(ecosystem)
        ECOSYSTEM_DEPENDENCY_GRAPH_MAP[ecosystem]
      end

      private

      # Include PURL type ecosystems if the advisory_db_purl_ecosystems_inbox
      # flag is enabled, OR if the dotcom side advisory_db_purl_ecosystems is
      # fully enabled.
      def include_purl_type_ecosystems?
        AdvisoryDB::Features.enabled?("advisory_db_purl_ecosystems_inbox") ||
          AdvisoryDB::Features.enabled?("advisory_db_purl_ecosystems")
      end
    end

    include Ecosystems
  end
end
