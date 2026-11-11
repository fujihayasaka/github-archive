# frozen_string_literal: true

# rubocop:disable Layout/FirstArrayElementIndentation
# rubocop:disable Rails/RakeEnvironment
namespace :enterprise do
  desc "create a tarball"
  task :tarball do
    require "rake/packagetask"

    Rake::PackageTask.new("dependabot", ENV["GITHUB_SHA"]) do |package|
      package.need_tar_gz = true
      package.package_files.add([
        ".ruby-version",
        "Gemfile*",
        "Procfile*",
        "Rakefile",
        "app/**/*",
        "bin/rails",
        "bin/timerd",
        "config.ru",
        "config/**/*",
        "db/**/*",
        "gen/**/*",
        "lib/**/*",
        "public/**/*",
        "script/hydro-enterprise-consumer",
        "static/*.json",
        "vendor/bundle/**/*",
        "vendor/licenses/**/*",
        "vendor/activejob-scheduled_job/**/*",
      ])
      exclusions = [
        "config/certs",
        "config/kubernetes",
        "config/moda",
        "config/resqued/aqueduct_throttled_worker.rb",
        "config/resqued/aqueduct_worker.rb",
        "vendor/certificates",
        %r{^proto/},
        %r{config/.+-dev.conf},
        %r{vendor/bundle/ruby/\d+\.\d+\.\d+/cache},
      ]
      package.package_files.exclude do |path|
        exclusions.any? { |exclusion| path.match?(exclusion) }
      end
    end
    Rake::Task["repackage"].invoke
  end
end
# rubocop:enable Layout/FirstArrayElementIndentation
# rubocop:enable Rails/RakeEnvironment
