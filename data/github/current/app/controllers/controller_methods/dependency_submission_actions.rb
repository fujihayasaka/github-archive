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

    # ordering of keys in order of priority. As per https://github.com/github/dependency-graph/issues/1552
    # Then the {name} key will take one value that is present, in this order: Gradle, Maven, sbt, Mill
    BUILD_TIME_MANIFESTS = %w[
      build.gradle
      build.gradle.kts
      pom.xml
      build.sbt
      build.sc
    ]

    # For these ecosystems we should refer the user to the Automatic dependency submission feature
    AUTO_DS_PATH = {
      "pom.xml" => "maven",
    }

    # For these ecosystems we should refer the user to the Actions marketplace
    DS_ACTIONS_PATH = {
      "build.gradle" => "gradle",
      "build.gradle.kts" => "gradle",
      "build.sbt" => "sbt",
      "build.sc" => "mill"
    }

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
          return false if GitHub.enterprise?
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
        "https://github.com/marketplace?query=dependency+submission+#{DS_ACTIONS_PATH[found_manifests.first]}"
      elsif found_manifests.length > 1
        "https://github.com/marketplace?query=dependency+submission+"
      end
    end

    def automatic_ds_ecosystem_name
      AUTO_DS_PATH[automatic_ds_manifests.first]&.capitalize
    end

    def action_ds_ecosystem_name
      priority_ecosystem = DS_ACTIONS_PATH[action_ds_manifests.first]
      if priority_ecosystem == "sbt"
        # https://github.com/github/dependency-graph/issues/1552#issuecomment-1370230722
        priority_ecosystem = "Scala"
      end
      priority_ecosystem&.capitalize
    end

    private

    def client
      @client ||= GitHub::Spokes::Client::Spokesd.instance
    end

    memoize def automatic_ds_manifests
      AUTO_DS_PATH.keys.select { |file| file.in?(found_manifests) }
    end

    memoize def action_ds_manifests
      DS_ACTIONS_PATH.keys.select { |file| file.in?(found_manifests) }
    end

    memoize def found_manifests
      track_execution_time("dependency_submission_action.dist.time", ["method:found_manifests"]) do
        default_ref = "refs/heads/#{current_repository.default_branch}"
        begin
          manifests = client.get_all_filepaths_from_repo(current_repository.id, default_ref,
                                                        file_extensions: BUILD_TIME_MANIFESTS,
                                                        recursive: false
                                                      )
          # select only exact matches. get_all_filepaths_from_repo checks end_with?
          BUILD_TIME_MANIFESTS.select { |file| file.in?(manifests) }
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
  end
end
