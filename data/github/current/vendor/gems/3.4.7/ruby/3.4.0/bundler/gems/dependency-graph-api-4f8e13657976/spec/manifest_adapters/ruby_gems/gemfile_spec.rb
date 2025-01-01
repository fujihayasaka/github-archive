require "rails_helper"

describe "Gemfile parsing" do
  let(:file) do
     <<-GEMFILE
      source 'https://rubygems.org'

      gem 'rake'
      gem 'fakeweb',  '~> 1.3'

      group :production do
        gem 'mongrel',  '1.2.0.pre2'
      end

      group :development do
        gem 'guard', github: 'guard/guard'
      end

      group :test do
        gem 'rspec',    '~> 3.4', '~> 4.0'
        gem 'simplecov', require: false
      end
    GEMFILE
  end

  def manifest(attributes = {})
    ManifestAdapters.parse(**{
      git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
      github_repository_id: 55,
      filename: "Gemfile",
      path: "",
      content: file,
      pushed_at: Time.now,
      fork: false,
      visibility_private: false,
    }.merge(attributes))
  end

  def dependency(args)
    ManifestAdapters::Manifest::Dependency.new(**args)
  end

  describe "#manifest_type" do
    it "is a Gemfile" do
      expect(manifest.manifest_type).to eq Types::Manifest[:gemfile]
    end
  end

  describe "#package_manager" do
    it "is rubygems" do
      expect(manifest.package_manager).to eq Types::PackageManager[:rubygems]
    end
  end

  describe "#dependent_name" do
    it "is nil" do
      expect(manifest.dependent_name).to be_nil
    end
  end

  describe "#dependent_version" do
    it "is the commit SHA" do
      expect(manifest.dependent_version).to be_nil
    end
  end

  describe "#git_ref" do
    it "returns the commit SHA" do
      expect(manifest.git_ref)
        .to eq "78716382bd3de2dbf141643bbe40f93185b5d4c6"
    end
  end

  describe "#github_repository_id" do
    it "returns the repo ID" do
      expect(manifest.github_repository_id).to eq 55
    end
  end

  describe "#dependencies" do
    it "parses dependencies" do
      expect(manifest.dependencies).to match_array [
        dependency(package_name: "rake", scope: :runtime, requirements:  ">= 0", raw_requirements:  ">= 0"),
        dependency(package_name: "fakeweb", scope: :runtime, requirements:  "~> 1.3", raw_requirements:  "~> 1.3"),
        dependency(package_name: "mongrel", scope: :runtime, requirements:  "= 1.2.0.pre2", raw_requirements:  "= 1.2.0.pre2"),
        dependency(package_name: "guard", scope: :development, requirements:  ">= 0", raw_requirements:  ">= 0"),
        dependency(package_name: "rspec", scope: :development, requirements:  "~> 3.4,~> 4.0", raw_requirements:  "~> 3.4,~> 4.0"),
        dependency(package_name: "simplecov", scope: :development, requirements:  ">= 0", raw_requirements:  ">= 0"),
      ]
    end

  end
end
