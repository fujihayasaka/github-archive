require "rails_helper"
require_relative "../../support/blob_operations_responses_helper"

describe "ingesting packages and manifests" do
  include ActiveJob::TestHelper

  let(:package_processor) { Ingest::PackageProcessor.new }
  let(:package_releases) { [] }
  let(:manifest_processor) { Ingest::RepositoryManifestFileChangeProcessor.new }
  let(:manifests) { [] }
  let(:responses_helper) { BlobOperationsResponseHelper.new }
  let (:blob_provider) { double(BlobOperations::Spokes::Client) }

  describe "packages with standard versioning" do
    before do
      package_releases << {
        package_manager: :rubygems,
        package_name:    "httparty",
        package_version: "0.40.0",
        published_at:    Time.new(2016, 10, 10).to_i,
        dependencies: [
          {
            package_name: "multi_xml",
            requirements: ">= 1.5.2,< 2.0.0",
            scope:        :runtime,
          },
          {
            package_name: "rake",
            requirements: ">= 0",
            scope:        :development
          },
        ]
      }

      package_releases << {
        package_manager: :rubygems,
        package_name:    "httparty",
        package_version: "0.50.0",
        published_at:    Time.new(2016, 10, 11).to_i,
        dependencies: [
          {
            package_name: "multi_xml",
            requirements: "~> 1.5.2",
            scope:        :runtime,
          },
          {
            package_name: "rake",
            requirements: ">= 0",
            scope:        :development,
          },
        ]
      }

      package_releases << {
        package_manager: :rubygems,
        package_name:    "rake",
        package_version: "11.4.0",
        published_at:    Time.new(2016, 10, 1).to_i,
        dependencies:    [],
      }

      package_releases << {
        package_manager: :rubygems,
        package_name:    "multi_xml",
        package_version: "1.5.2",
        published_at:    Time.new(2016, 10, 2).to_i,
        dependencies:    [],
      }

      package_releases << {
        package_manager: :rubygems,
        package_name:    "multi_xml",
        package_version: "1.6.2",
        published_at:    Time.new(2016, 10, 3).to_i,
        dependencies:    [],
      }

      package_releases << {
        package_manager: :rubygems,
        package_name:    "multi_xml",
        package_version: "1.6.3",
        published_at:    Time.new(2016, 10, 3).to_i,
        unpublished_at:  Time.new(2016, 10, 4).to_i,
        dependencies:    [],
      }

      package_releases << {
        package_manager: :rubygems,
        package_name:    "guard",
        package_version: "1.0.0",
        published_at:    Time.new(2016, 10, 4).to_i,
        dependencies:    [],
      }

      manifests << {
        repository_id: 12,
        owner_id: 300,
        repository_nwo: "foo/bar",
        repository_stargazer_count: 14,
        repository_private: false,
        repository_fork: false,
        is_backfill: false,
        manifest_file: {
          filename: "httparty.gemspec",
          path: "",
          git_ref: "89f3e9",
          pushed_at: Time.new(2016, 10, 10).to_i
        }
      }

      manifests << {
        repository_id: 5,
        owner_id: 300,
        repository_nwo: "foo/bar2",
        repository_stargazer_count: 15,
        repository_private: false,
        repository_fork: false,
        is_backfill: false,
        manifest_file: {
          filename: "multi_xml.gemspec",
          path: "",
          git_ref: "0e0575",
          pushed_at: Time.new(2016, 10, 11).to_i
        }
      }

      manifests << {
        repository_id: 109,
        owner_id: 300,
        repository_nwo: "foo/bar3",
        repository_stargazer_count: 19,
        repository_private: false,
        repository_fork: false,
        is_backfill: false,
        manifest_file: {
          filename: "Gemfile",
          path: "",
          git_ref: "eb2519c",
          pushed_at: Time.new(2016, 10, 12).to_i
        }
      }

      allow(Repository).to receive(:find_by).and_return(nil)
      blob_response = responses_helper.blob_response(
        content: "gem 'httparty',  '~> 0.50.0'",
        size_bytes: 20
      )
      manifests.each do |manifest|
        allow_any_instance_of(ProcessManifestJob).to receive(:blob_provider).and_return(blob_provider)
        allow(blob_provider).to receive(:get_blob).with(repository_id: manifest[:repository_id], oid: "").and_return(blob_response)
        allow(Repository).to receive(:find_by).with(github_repository_id: manifest[:repository_id]).and_return(Repository.new(github_repository_id: manifest[:repository_id]))
      end

      run_all_stages
      run_all_stages # Ensure ingestion is idempotent
    end

    it "imports 4 packages" do
      expect(Package.count).to eq 4
    end

    it "imports 1 repo" do
      expect(Repository.count).to eq 3
    end

    it "imports `rake`" do
      rake = get_package("rake")
      expect(rake.package_manager).to eq Types::PackageManager[:rubygems]
      expect(rake.releases.count).to eq 1
      expect(rake.releases.first.dependencies).to be_empty
      expect(rake.releases.first.published_at).to eq Time.new(2016, 10, 1)
      expect(rake.last_published_at).to eq(Time.new(2016, 10, 1))
    end

    it "imports `multi_xml`" do
      multi_xml = get_package("multi_xml")
      expect(multi_xml.package_manager).to eq Types::PackageManager[:rubygems]
      expect(multi_xml.releases.published.count).to eq 2
      expect(multi_xml.releases.published.first.dependencies).to be_empty
      expect(multi_xml.last_published_at).to eq(Time.new(2016, 10, 3))
    end

    it "imports the first version of `multi_xml`" do
      multi_xml_v1 = get_package_release("multi_xml", "1.5.2")
      expect(multi_xml_v1.dependencies).to be_empty
      expect(multi_xml_v1.published_at).to eq Time.new(2016, 10, 2)
    end

    it "imports the second version of `multi_xml`" do
      multi_xml_v2 = get_package_release("multi_xml", "1.6.2")
      expect(multi_xml_v2.dependencies.count).to be_zero
      expect(multi_xml_v2.published_at).to eq Time.new(2016, 10, 3)
    end

    it "imports the yanked version of `multi_xml`" do
      multi_xml        = get_package("multi_xml")
      multi_xml_yanked = PackageRelease.where({
        package_id: multi_xml,
        name:       "1.6.3",
      }).first
      expect(multi_xml_yanked.dependencies).to be_empty
      expect(multi_xml_yanked.published_at).to eq Time.new(2016, 10, 3)
      expect(multi_xml_yanked.unpublished_at).to eq Time.new(2016, 10, 4)
    end

    it "imports `httparty`" do
      httparty = get_package("httparty")
      expect(httparty.package_manager).to eq Types::PackageManager[:rubygems]
      expect(httparty.releases.count).to eq 2
      expect(httparty.last_published_at).to eq(Time.new(2016, 10, 11))
    end

    it "imports the first version of `httparty`" do
      httparty_v1 = get_package_release("httparty", "0.40.0")
      expect(httparty_v1.dependencies.count).to eq 2

      expect(dependencies(httparty_v1)).to match_array [
        get_package("multi_xml"),
        get_package("rake")
      ]
      expect(runtime_dependencies(httparty_v1)).to match_array [
        get_package("multi_xml"),
      ]
      expect(dev_dependencies(httparty_v1)).to match_array [
        get_package("rake"),
      ]
      expect(httparty_v1.published_at).to eq Time.new(2016, 10, 10)
    end

    it "imports the second version of `httparty`" do
      httparty_v2 = get_package_release("httparty", "0.50.0")
      expect(httparty_v2.dependencies.count).to eq 2

      expect(dependencies(httparty_v2)).to match_array [
        get_package("multi_xml"),
        get_package("rake")
      ]
      expect(runtime_dependencies(httparty_v2)).to match_array [
        get_package("multi_xml"),
      ]
      expect(dev_dependencies(httparty_v2)).to match_array [
        get_package("rake"),
      ]
      expect(httparty_v2.published_at).to eq Time.new(2016, 10, 11)
    end

    it "imports the repository" do
      repo = Repository.where(github_repository_id: 109).first!

      expect(repo.manifests.count).to eq 1
    end

    it "imports the manifest from the repo" do
      repo     = Repository.where(github_repository_id: 109).first!
      manifest = repo.manifests.last

      expect(manifest.latest_git_ref).to eq "eb2519c"
      expect(manifest.last_pushed_at).to eq Time.new(2016, 10, 12)
      expect(manifest.entries.count).to eq 1
    end
  end

  it "handles packages with unorthodox versioning schemes" do
    package_processor.spec_reset

    releases = []

    releases << {
      package_manager: :rubygems,
      package_name:    "httparty",
      package_version: "0.40.0",
      dependencies: [
        {
          package_name: "multi_xml",
          requirements: ">= 2016-10-01",
          scope:        :runtime,
        }
      ]
    }

    releases << {
      package_manager: :rubygems,
      package_name:    "multi_xml",
      package_version: "2016-10-01",
      dependencies:    [],
    }

    releases << {
      package_manager: :rubygems,
      package_name:    "multi_xml",
      package_version: "2016-10-05",
      dependencies:    [],
    }

    releases.each { |release| package_processor.publish(release) }

    run_all_stages

    expect(Package.count).to eq 2

    version = get_package_release("httparty", "0.40.0")
    expect(version.dependencies.count).to eq 1

    expect(dependencies(version)).to match_array [
      get_package("multi_xml"),
    ]
    expect(runtime_dependencies(version)).to match_array [
      get_package("multi_xml"),
    ]
    expect(dev_dependencies(version)).to be_empty

    package_processor.spec_reset
  end

  def dependencies(version)
    version.dependencies.map(&:package)
  end

  def runtime_dependencies(version)
    version.dependencies.runtime.map(&:package)
  end

  def dev_dependencies(version)
    version.dependencies.development.map(&:package)
  end

  def run_all_stages
    manifest_topic = Rails.application.config_for(:kafka).with_indifferent_access.fetch(:repo_manifest_file_change_topic)
    package_releases.each { |release| package_processor.publish(release) }
    perform_enqueued_jobs { run_consumer(package_processor) }
    manifests.each { |manifest| manifest_processor.publish(manifest, topic: manifest_topic) }
    perform_enqueued_jobs { run_consumer(manifest_processor) }
  rescue Trilogy::Error => e
    raise e unless e.error_number.to_s == "0"
  end
end
