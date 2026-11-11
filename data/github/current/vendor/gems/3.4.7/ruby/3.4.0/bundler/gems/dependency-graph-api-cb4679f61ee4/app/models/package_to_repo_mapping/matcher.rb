module PackageToRepoMapping
  class Matcher
    class_attribute :certainty, :package_managers
    self.package_managers = Types::PackageManager.to_a

    # Computes the repository probably associated with the package
    # using various heuristics, and updates the Repository relation.
    # May update fields of package.
    def self.process(package)
      return if package.repository_id_certainty == PackageToRepoMapping::Certainty::OVERRIDE || package.repository_id_certainty == PackageToRepoMapping::Certainty::POSITIVE_MATCH

      # If our current mapping is UNVERIFIED, we will try all the more certain matchers in order and update if one hits
      # Otherwise, we run the UnverifiedMatcher as well, and reset our repository id and certainty so that all matchers get a chance to run.
      # This is because previously valid mappings can be invalid (e.g. a manifest was deleted) and we want to default to the unverified mapping
      # We don't run the unverified mapping if there already is one since it's set by the package importer and re running the mapper means traversing every package's package releases which can be expensive

      # Order of this list is not significant: it is sorted below by certainty.
      matchers = [
        MavenAmbiguousMatcher,
        NugetAmbiguousMatcher,
        StrongMatcher,
        WeakMatcher,
      ]

      if package.repository_id_certainty != PackageToRepoMapping::Certainty::UNVERIFIED
        matchers << UnverifiedMatcher
        package.repository_id_certainty = 0
        package.repository_id = nil
      end

      # NOTE: Ensure that the order of this Array is based off of the Matcher certainty, from highest to lowest.
      # We need to do this because we'd like to break out of the each loop below once we get a repo_id.
      # In order to do that safely, we need the highest certainty to be processed first!
      matchers = matchers.sort_by(&:certainty).reverse
      matchers.each do |matcher|
        if valid_matcher?(matcher, package)
          Instrument.time("package_to_repo_mapping.matcher", matcher: matcher.name.demodulize.underscore) do
            break if matcher.match!(package)
          end
        end
      end
    end

    # Find and record a match (called on the subclasses)
    def self.match!(package)
      begin
        repo = ActiveRecord::Base.connected_to(role: :reading) do
          find_repo(package)
        end

        return unless repo

        ActiveRecord::Base.connected_to(role: :writing) do
          record_match!(package, repo)
        end
      rescue ActiveRecord::StatementInvalid => e
        Instrument.increment("etl.package_to_repo_mapping.error")
        # Our mysql database doesn't accept UTF-8 values for some tables that use 4-byte chars (e.g. emojis)
        if e.message.include?("Incorrect string value") || e.message.include?("Illegal mix of collations")
          Instrument.increment("etl.package_to_repo_mapping.error.four_byte_utf")
          Failbot.report(e, "gh.dependency_graph.etl.step.name" => "etl.package_to_repo_mapping")
        else
          # re-raise if it's not a utf error
          raise e
        end
      end
    end

    # Record a found match (called on the subclasses)
    def self.record_match!(package, repo)
      package.update!(
        repository_id: repo.github_repository_id,
        repository_id_certainty: certainty
      )
    end
    # Is this matcher a valid matcher for the package?
    def self.valid_matcher?(matcher, package)
      # Matchers are valid if they support the package manager and
      # have a higher certainty than the highest we have for the
      # given package
      matcher.package_managers.include?(package.package_manager) &&
        package.repository_id_certainty <= matcher.certainty
    end
  end
end
