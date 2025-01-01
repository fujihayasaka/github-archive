module SnapshotGenerators
  class Dependency
    def self.gen_name
      Rantly { choose("alpha", "beta", "gamma", "delta", "epsilon", string) }
    end

    def self.gen_version
      xyz = Rantly {
        x = range(0, 1000)
        y = range(0, 1000)
        z = range(0, 1000)
        "#{x}.#{y}.#{z}"
      }
      Rantly {
        choose(
          xyz,
          Rantly {
            prefix = xyz
            tag = Rantly {
              choose(
                "SNAPSHOT",
                "BETA",
                "pre",
                string
                )
            }
            "#{prefix}-#{tag}"
          },
          string
          )
      }
    end

    def self.gen_scope
      Rantly { choose("development", "runtime", nil) }
    end

    # it's helpful to have some commonly-occurring elements in snapshots
    # to test updates and whatnot
    def self.generate_common
      Rantly {
        name = "common"
        version = choose("1.0.0", "1.0.1", "2.0.0", "2.0.1")
        scope = SnapshotGenerators::Dependency.gen_scope
        Snapshots::Dependency.new(name: name, version: version, scope: scope)
      }
    end

    def self.generate_uncommon
      Rantly {
        name = SnapshotGenerators::Dependency.gen_name
        version = SnapshotGenerators::Dependency.gen_version
        scope = SnapshotGenerators::Dependency.gen_scope
        Snapshots::Dependency.new(name: name, version: version, scope: scope)
      }
    end

    def self.generate
      Rantly {
        # Generate common about 1/12 of the time
        x = range(1, 12)
        if x == 1
          SnapshotGenerators::Dependency.generate_common
        else
          SnapshotGenerators::Dependency.generate_uncommon
        end
      }
    end
  end

  class DependencySnapshotDependency
    def self.gen_name
      Rantly { choose("alpha", "beta", "gamma", "delta", "epsilon", "node", "%40angular/animation") }
    end

    def self.gen_version
      Rantly {
        x = range(0, 1000)
        y = range(0, 1000)
        z = range(0, 1000)
        "#{x}.#{y}.#{z}"
      }
    end

    def self.gen_scope
      Rantly {
        choose(range(1, Snapshots::DependencySnapshotDependencyScope::TEST_COMPILE * 2))
      }
    end

    def self.gen_explicit
      Rantly {
        choose(true, false)
      }
    end

    def self.gen_purl
      purls_pkm = Rantly {
        choose(
          "nuget",
          "composer",
          "cargo",
          "maven",
          "gem",
          "npm",
          "golang",
          "pypi",
          "bitbucket",
        )
      }

      name = Rantly {
        SnapshotGenerators::DependencySnapshotDependency.gen_name
      }

      version = Rantly {
        SnapshotGenerators::DependencySnapshotDependency.gen_version
      }

      "pkg:#{purls_pkm}/#{name}@#{version}"
    end

    def self.generate_dep_without_purl
      Rantly {
        len = range(0, 5)
        scope = SnapshotGenerators::DependencySnapshotDependency.gen_scope
        explicit = SnapshotGenerators::DependencySnapshotDependency.gen_explicit
        dependencies = array(len) {
          SnapshotGenerators::DependencySnapshotDependency.gen_purl
        }

        {
          scope: scope,
          explicit: explicit,
          dependencies: dependencies
        }
      }
    end

    def self.generate_dep_with_purl
      Rantly {
        len = range(0, 5)
        scope = SnapshotGenerators::DependencySnapshotDependency.gen_scope
        explicit = SnapshotGenerators::DependencySnapshotDependency.gen_explicit
        dependencies = array(len) {
          SnapshotGenerators::DependencySnapshotDependency.gen_purl
        }

        hash = {}
        hash[SnapshotGenerators::DependencySnapshotDependency.gen_purl] = {
          scope: scope,
          explicit: explicit,
          dependencies: dependencies
        }

        hash
      }
    end
  end
end
