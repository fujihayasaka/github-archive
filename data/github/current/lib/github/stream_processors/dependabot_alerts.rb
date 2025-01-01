# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module DependabotAlerts
      autoload :AlertingProgressProcessor, "github/stream_processors/dependabot_alerts/alerting_progress_processor"
      autoload :DeletedManifestProcessor, "github/stream_processors/dependabot_alerts/deleted_manifest_processor"
      autoload :ManifestVulnerableDependenciesProcessor, "github/stream_processors/dependabot_alerts/manifest_vulnerable_dependencies_processor"
      autoload :VulnerableDependencyProcessor, "github/stream_processors/dependabot_alerts/vulnerable_dependency_processor"
    end
  end
end
