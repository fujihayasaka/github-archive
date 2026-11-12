module PackageToRepoMapping
  class OverrideMatcher < Matcher
    self.certainty = Certainty::OVERRIDE

    # This matcher is only called directly, never by
    # `Matcher#process`, so it shouldn't be "valid" for any package
    # managers.
    self.package_managers = []
  end
end
