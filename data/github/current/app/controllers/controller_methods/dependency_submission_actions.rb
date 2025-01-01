# typed: true
# frozen_string_literal: true

module ControllerMethods
  module DependencySubmissionActions
    extend T::Helpers
    extend ActiveSupport::Concern
    include GitHub::Memoizer
    include GitHub::ResilienceMixin

    requires_ancestor { ApplicationController }

    included do
      T.bind(self, T.class_of(ApplicationController))

      helper_method :has_ds_action_ecosystem?
      helper_method :show_automatic_submission_prompt?
      helper_method :show_submission_prompt?
      helper_method :ds_marketplace_action_link
      helper_method :action_ds_ecosystem_name
      helper_method :automatic_ds_ecosystem_name
    end

    # Ecosystem display names
    MAVEN_ECOSYSTEM = "Maven"
    GRADLE_ECOSYSTEM = "Gradle"
    SCALA_ECOSYSTEM = "Scala"
    MILL_ECOSYSTEM = "Mill"
    GO_ECOSYSTEM = "Go"
    NUGET_ECOSYSTEM = "NuGet"
    PYTHON_ECOSYSTEM = "Python"

    # ordering of keys in order of priority. As per https://github.com/github/dependency-graph/issues/1552
    # Then the {name} key will take one value that is present, in this order: Gradle, Maven, sbt, Mill
    BUILD_TIME_MANIFESTS = {
      "build.gradle" => { exact_match: true },
      "build.gradle.kts" => { exact_match: true },
      "pom.xml" => { exact_match: true },
      "build.sbt" => { exact_match: true },
      "build.sc" => { exact_match: true },
      "go.mod" => { exact_match: true },
      "requirements.txt" => { exact_match: true },
      "packages.config" => { exact_match: true },
      # `.csproj`, `.sln`, `.vbproj`, `.vcxproj`, and `.fsproj` use `exact_match: false` because these patterns match file extensions
      # rather than full filenames, allowing for broader compatibility with files in the ecosystem.
      ".csproj" => { exact_match: false },
      ".sln" => { exact_match: false },
      ".vbproj" => { exact_match: false },
      ".vcxproj" => { exact_match: false },
      ".fsproj" => { exact_match: false }
    }

    # For these ecosystems we should refer the user to the Automatic dependency submission feature
    AUTO_DS_PATH = {
      "pom.xml" => MAVEN_ECOSYSTEM,
      "build.gradle" => GRADLE_ECOSYSTEM,
      "build.gradle.kts" => GRADLE_ECOSYSTEM,
      "gradlew" => GRADLE_ECOSYSTEM,
      ".csproj" => NUGET_ECOSYSTEM,
      ".sln" => NUGET_ECOSYSTEM,
      "packages.config" => NUGET_ECOSYSTEM,
      ".vbproj" => NUGET_ECOSYSTEM,
      ".vcxproj" => NUGET_ECOSYSTEM,
      ".fsproj" => NUGET_ECOSYSTEM,
      "requirements.txt" => PYTHON_ECOSYSTEM,
    }

    # For these ecosystems we should refer the user to the Actions marketplace
    DS_ACTIONS_PATH = {
      "build.sbt" => "sbt",
      "build.sc" => "mill",
      "go.mod" => "go"
    }

    # Go is a feature enabled auto submission ecosystem
    # Feature flag: :dependency_graph_autosubmission_golang_support
    GO_FEATURE_ENABLED_PATHS = {
      "go.mod" => GO_ECOSYSTEM,
    }

    def auto_ds_path
      AUTO_DS_PATH.merge(feature_enabled_ecosystems_auto_ds_paths)
    end

    def ds_actions_path
      DS_ACTIONS_PATH.except(*feature_enabled_ecosystems_auto_ds_paths.keys)
    end

    memoize def has_automatic_ds_ecosystem?
      return false unless found_manifests.any?

      automatic_ds_manifests.any?
    end

    def has_ds_action_ecosystem?
      return false unless found_manifests.any?

      action_ds_manifests.any?
    end

    def show_submission_prompt?
      with_database_error_fallback(fallback: false) do
        track_execution_time("dependency_submission_action.dist.time", ["method:show_submission_prompt?"]) do
          return false unless logged_in?
          return false if current_user.dismissed_notice?(UserNotice::DS_ACTION_PROMPT_NOTICE)
          current_repository.adminable_by?(current_user) && has_ds_action_ecosystem?
        end
      end
    end

    def show_automatic_submission_prompt?
      with_database_error_fallback(fallback: false) do
        track_execution_time("dependency_submission_action.dist.time", ["method:show_automatic_submission_prompt?"]) do
          return false unless logged_in?
          return false if current_user.dismissed_notice?(UserNotice::AUTOMATIC_DEPENDENCY_SUBMISSION_BANNER_NOTICE)
          return false unless current_repository.adminable_by?(current_user) && has_automatic_ds_ecosystem?

          # Don't show the banner if they're already using the feature
          !SecurityProduct::DependencyGraphAutosubmitAction.new(current_repository).enabled?
        end
      end
    end

    def ds_marketplace_action_link
      if found_manifests.length == 1
        "https://github.com/marketplace?query=dependency+submission+#{ds_actions_path[found_manifests.first]}"
      elsif found_manifests.length > 1
        "https://github.com/marketplace?query=dependency+submission+"
      end
    end

    def automatic_ds_ecosystem_name
      auto_ds_path[automatic_ds_manifests.first]
    end

    def action_ds_ecosystem_name
      priority_ecosystem = ds_actions_path[action_ds_manifests.first]
      if priority_ecosystem == "sbt"
        # https://github.com/github/dependency-graph/issues/1552#issuecomment-1370230722
        priority_ecosystem = "Scala"
      end
      priority_ecosystem&.capitalize
    end

    private

    def feature_enabled_ecosystems_auto_ds_paths
      ecosystems = {}
      if FeatureFlag.vexi.enabled?(:dependency_graph_autosubmission_golang_support, current_repository, default: false)
        ecosystems.merge!(GO_FEATURE_ENABLED_PATHS)
      end
      ecosystems
    end

    memoize def automatic_ds_manifests
      auto_ds_path.keys.select { |file| file.in?(found_manifests) }
    end

    memoize def action_ds_manifests
      ds_actions_path.keys.select { |file| file.in?(found_manifests) }
    end

    memoize def found_manifests
      track_execution_time("dependency_submission_action.dist.time", ["method:found_manifests"]) do
        default_ref = "refs/heads/#{current_repository.default_branch}"
        begin
          # Get all file extensions/names we're looking for
          search_patterns = BUILD_TIME_MANIFESTS.keys
          manifests = get_all_filepaths_from_repo(
            default_ref,
            file_extensions: search_patterns,
            recursive: false
          )

          # Filter based on exact match or extension matching
          BUILD_TIME_MANIFESTS.each_with_object([]) do |(pattern, config), found|
            matches = config[:exact_match] ? pattern.in?(manifests) : manifests.any? { |manifest| manifest.end_with?(pattern) }
            found << pattern if matches
          end
        rescue RuntimeError
          # Avoid raising 500s for users on a RuntimeError (as in the case where spokesd is not
          # enabled, has a connection error, etc), this will result in us failing over to hiding
          # the related banners.
          []
        end
      end
    end

    def track_execution_time(metric, tags = [])
      timer = Timer.start
      result = yield
      timer.stop
      GitHub.dogstats.distribution(metric, timer.elapsed_ms, tags: tags)
      result
    end

    sig { params(reference_name: String, file_extensions: T.nilable(T::Array[String]), recursive: T::Boolean).returns(T::Array[String]) }
    def get_all_filepaths_from_repo(reference_name, file_extensions: nil, recursive: true)
      file_paths = Array.new
      selector = {
        treeish_selector: {
          treeish: { reference: { name: reference_name } },
        }
      }

      SpokesAPI::Client.paged_responses do |cursor|
        current_repository.spokes_api.list_tree_entries_by(selector, recursive:, cursor:)
      end.each do |resp|
        resp.entries.each do |entry|
          if entry.object.type == :TYPE_BLOB && (
            file_extensions.nil? || file_extensions.empty? || entry.path.name.end_with?(*file_extensions)
          )
            file_paths << entry.path.name
          end
        end
      end

      file_paths
    end
  end
end
