require "rails_helper"

describe "gemspec parsing" do
  let(:file) do
    <<~GEMSPEC
      $LOAD_PATH.push File.expand_path("../lib", __FILE__)
      require "httparty/version"

      Gem::Specification.new do |s|
        s.name        = "httparty"
        s.version     = HTTParty::VERSION
        s.platform    = Gem::Platform::RUBY
        s.licenses    = ['MIT']
        s.authors     = ["John Nunemaker", "Sandro Turriate"]
        s.email       = ["nunemaker@gmail.com"]
        s.homepage    = "http://jnunemaker.github.com/httparty"
        s.description = 'Makes http fun! Also, makes consuming restful web services dead easy.'

        s.required_ruby_version     = '>= 2.0.0'

        s.add_dependency "multi_xml", ">= 0.5.2"
        s.add_development_dependency "rspec", "~> 3.4", "~> 4.0"

        s.files         = `git ls-files`.split("\n")
        s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
        s.executables   = `git ls-files -- bin/*`.split("\n").map { |f| File.basename(f) }
        s.require_paths = ["lib"]
      end
    GEMSPEC
  end

  def build_manifest(attributes = {})
    ManifestAdapters.parse(**{
      git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
      github_repository_id: 55,
      filename: "httparty.gemspec",
      content: file,
      path: nil,
      pushed_at: Time.now,
      fork: false,
      visibility_private: false,
    }.merge(attributes))
  end

  def dependency(args)
    ManifestAdapters::Manifest::Dependency.new(**args)
  end

  let(:manifest) { build_manifest }

  describe "#manifest_type" do
    it "is a gemspec" do
      expect(manifest.manifest_type).to eq Types::Manifest[:gemspec]
    end
  end

  describe "#package_manager" do
    it "is rubygems" do
      expect(manifest.package_manager).to eq Types::PackageManager[:rubygems]
    end
  end

  describe "#dependent_name" do
    it "reads the name attribute" do
      expect(manifest.dependent_name).to eq "httparty"
    end

    it "handles single quoted strings" do
      manifest = build_manifest({
        content: <<~GEMSPEC
          require "httparty/version"

          Gem::Specification.new do |s|
            s.name   = 'httparty'
            s.add_dependency "multi_xml", ">= 0.5.2"
            s.add_development_dependency "rspec", "~> 3.4"
          end
        GEMSPEC
      })

      expect(manifest.dependent_name).to eq "httparty"
    end

    it "handles %q{} quoted strings" do
      manifest = build_manifest({
        content: <<~GEMSPEC
          require "httparty/version"

          Gem::Specification.new do |s|
            s.name= %q{ httparty }
            s.add_dependency "multi_xml", ">= 0.5.2"
            s.add_development_dependency "rspec", "~> 3.4"
          end
        GEMSPEC
      })

      expect(manifest.dependent_name).to eq "httparty"
    end
  end

  describe "#dependent_version" do
    it "uses a specified version when available" do
      manifest = build_manifest({
        content: <<~GEMSPEC
          require "httparty/version"

          Gem::Specification.new do |s|
            s.version = "1.0.0.beta"
            s.add_dependency "multi_xml", ">= 0.5.2"
            s.add_development_dependency "rspec", "~> 3.4"
          end
        GEMSPEC
      })

      expect(manifest.dependent_version).to eq "1.0.0.beta"
    end

    it "ignores constants" do
      manifest = build_manifest({
        content: <<~GEMSPEC
          require "httparty/version"

          Gem::Specification.new do |s|
            s.version = HTTParty::VERSION
            s.add_dependency "multi_xml", ">= 0.5.2"
            s.add_development_dependency "rspec", "~> 3.4"
          end
        GEMSPEC
      })

      expect(manifest.dependent_version).to be_nil
    end

    it "ignores variables" do
      manifest = build_manifest({
        content: <<~GEMSPEC
          require "httparty/version"

          Gem::Specification.new do |s|
            version = "1.0.0.beta"
            s.version = version
            s.add_dependency "multi_xml", ">= 0.5.2"
            s.add_development_dependency "rspec", "~> 3.4"
          end
        GEMSPEC
      })

      expect(manifest.dependent_version).to be_nil
    end

    it "defaults to nil" do
      expect(manifest.dependent_version).to be_nil
    end
  end

  describe "#git_ref" do
    it "returns the commit SHA" do
      expect(manifest.git_ref).to eq "78716382bd3de2dbf141643bbe40f93185b5d4c6"
    end
  end

  describe "#github_repository_id" do
    it "returns the repo ID" do
      expect(manifest.github_repository_id).to eq 55
    end
  end

  describe "#path" do
    it "returns the spec path" do
      expect(build_manifest(path: nil).path).to eq ""
      expect(build_manifest(path: "vendor/gem").path).to eq "vendor/gem"
    end
  end

  describe "#dependencies" do
    it "parses dependencies" do
      expect(manifest.dependencies).to match_array [
        dependency(package_name: "multi_xml", scope: :runtime, requirements: ">= 0.5.2", raw_requirements: ">= 0.5.2"),
        dependency(package_name: "rspec", scope: :development, requirements: "~> 3.4,~> 4.0", raw_requirements: "~> 3.4,~> 4.0"),
      ]
    end
  end
end
