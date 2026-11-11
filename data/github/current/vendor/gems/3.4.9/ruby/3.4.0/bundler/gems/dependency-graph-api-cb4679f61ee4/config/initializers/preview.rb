# https://guides.rubyonrails.org/autoloading_and_reloading_constants.html#autoloading-when-the-application-boots
# This doesn't really reload today, I suspect because we're using other preloaders (bootsnap, spring?)
# That's not really the end of the world, and this code does help us avoid the deprecation warning.
Rails.application.reloader.to_prepare do
  # This file defines which package managers and manifest types are in preview
  # mode. Package managers and manifest types in preview mode are only visible
  # when the `preview` flag is passed to GraphQL queries. In practice,
  # github/github uses the `preview` flag to scope preview data to staff only.
  DependencyGraph::PACKAGE_MANAGER_PREVIEW = [
    # example entry: Types::PackageManager[:pub],
  ].freeze unless defined?(DependencyGraph::PACKAGE_MANAGER_PREVIEW)

  DependencyGraph::MANIFEST_TYPE_PREVIEW = [
    # example entry: Types::Manifest[:pubspec_lock],
    # example entry: Types::Manifest[:pubspec_yaml],
    Types::Manifest[:vendored_javascript_dependency],
  ].freeze unless defined?(DependencyGraph::MANIFEST_TYPE_PREVIEW)
end
