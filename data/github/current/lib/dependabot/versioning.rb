# typed: true
# frozen_string_literal: true
module Dependabot
  module Versioning
    autoload :Version, "dependabot/versioning/version"
    autoload :Python, "dependabot/versioning/python"
    autoload :Cargo, "dependabot/versioning/cargo"
    autoload :Composer, "dependabot/versioning/composer"
    autoload :GithubActions, "dependabot/versioning/github_actions"
    autoload :GoModules, "dependabot/versioning/go_modules"
    autoload :Hex, "dependabot/versioning/hex"
    autoload :Maven, "dependabot/versioning/maven"
    autoload :NpmAndYarn, "dependabot/versioning/npm_and_yarn"
    autoload :Nuget, "dependabot/versioning/nuget"
    autoload :Pub, "dependabot/versioning/pub"
    autoload :Bundler, "dependabot/versioning/bundler"
  end
end
