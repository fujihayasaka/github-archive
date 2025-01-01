module SnapshotGenerators
  class Manifest
    def self.gen_path
      star_gemspec = Rantly {
        s = string
        prefix = Shellwords.escape(s)
        "#{prefix}.gemspec"
      }
      filename = Rantly {
        choose(
          # Composer
          "composer.json",
          "composer.lock",
          # dotnet
          ".csproj",
          ".vbproj",
          ".nuspec",
          ".vcxproj",
          ".fsproj",
          "packages.config",
          # maven
          "pom.xml",
          # npm
          "package.json",
          "package-lock.json",
          # python
          "requirements.txt",
          "pypi-requirements.txt",
          "pipfile.lock",
          "setup.py",
          # rubygems
          "Gemfile",
          "Gemfile.lock",
          star_gemspec,
          # yarn
          "yarn.lock"
          )
      }
      dir = Rantly {
        len = range(0, 10)
        segments = array(len) {
          s = string
          Shellwords.escape(s)
        }
        segments.join("/")
      }

      "#{dir}/#{filename}"
    end

    def self.gen_oid
      Rantly {
        digits = array(40) { choose("0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f") }
        digits.join
      }
    end

    def self.generate
      Rantly {
        path = SnapshotGenerators::Manifest.gen_path
        oid = SnapshotGenerators::Manifest.gen_oid
        deps_count = range(1, 100)
        dependencies = array(deps_count) { SnapshotGenerators::Dependency.generate }
        Snapshots::Manifest.new(path: path, oid: oid, dependencies: dependencies.uniq)
      }
    end
  end

  class BuildManifest
    def self.gen_path
      filename = Rantly {
        choose(
          # Composer
          "composer.json",
          "composer.lock",
          # dotnet
          ".csproj",
          ".vbproj",
          ".nuspec",
          ".vcxproj",
          ".fsproj",
          "packages.config",
          # maven
          "pom.xml",
          # npm
          "package.json",
          "package-lock.json",
          # python
          "requirements.txt",
          "pypi-requirements.txt",
          "pipfile.lock",
          "setup.py",
          # rubygems
          "Gemfile",
          "Gemfile.lock",
          # yarn
          "yarn.lock"
        )
      }
      dir = Rantly {
        len = range(0, 10)
        segments = array(len) {
          s = string
          Shellwords.escape(s)
        }
        segments.join("/")
      }

      "#{dir}/#{filename}"
    end

    def self.gen_graph
      # scope is a flag (bitsum)
      Rantly {
        len = range(0, 5)
        dependencies = array(len) { SnapshotGenerators::DependencySnapshotDependency.generate_dep_without_purl }
        hash = {}
        dependencies.each { |dep|
          hash[SnapshotGenerators::DependencySnapshotDependency.gen_purl] = dep
        }

        hash
      }
    end

    def self.generate
      Rantly {
        hash = {}
        # generate key as plain ol' string, not as symbol
        hash["graph"] = SnapshotGenerators::BuildManifest.gen_graph
        hash
      }
    end
  end
end
