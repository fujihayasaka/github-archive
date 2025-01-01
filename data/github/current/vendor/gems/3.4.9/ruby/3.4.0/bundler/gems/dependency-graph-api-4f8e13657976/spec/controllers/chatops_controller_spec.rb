require "rails_helper"

describe ChatopsController, type: :controller do
  include ActiveJob::TestHelper

  before do
    chatops_auth!
    chatops_prefix "dg"
  end

  describe "various chatop commands" do

    context "echoing" do
      it "echos back" do
        chat "dg echo foo bar baz", "random_user"
        expect(chatop_response).to include("foo bar baz")
      end
    end

    context "pinging" do
      it "pongs back" do
        chat "dg ping", "random_user"
        expect(chatop_response).to include("pong!")
      end
    end

    context "blocklist" do
      it "returns packages" do
        chat "dg blocklist packages", "random_user"
        expect(chatop_response).to include("Blocklisted packages:")
      end

      it "returns manifest repos" do
        chat "dg blocklist repos", "random_user"
        expect(chatop_response).to include("Blocklisted manifest repos:")
      end

      it "informs user of incorrect input" do
        chat "dg blocklist blah", "random_user"
        expect(chatop_error).to include("didn't input a valid")
      end
    end

    context "blocklist add" do
      it "adds to specific blocklist" do
        Ingest::Blocklist.clear(type: :manifest_repos)
        chat "dg blocklist repos add 12345", "random_user"
        expect(chatop_response).to include("Sucessfully added")
        chat "dg blocklist repos add 1544, sarah/sarahscoolrepo", "random_user"
        blocklist = Ingest::Blocklist.view(type: :manifest_repos)
        expect(blocklist.size).to eq(3)
        expect(blocklist).to include("12345")
        expect(blocklist).to include("1544")
        expect(blocklist).to include("sarah/sarahscoolrepo")
        Ingest::Blocklist.clear(type: :manifest_repos)
      end

      it "adds package arrays sucessfully" do
        Ingest::Blocklist.clear(type: :packages)
        chat "dg blocklist packages add sarahsarah npm", "random_user"
        expect(chatop_response).to include("Sucessfully added")
        blocklist = Ingest::Blocklist.view(type: :packages)
        expect(blocklist.size).to eq(1)
        expect(blocklist).to include("sarahsarah:npm")
        Ingest::Blocklist.clear(type: :packages)
      end

      it "ignores incorrect package array additions" do
        Ingest::Blocklist.clear(type: :packages)
        chat "dg blocklist packages add sarahsarah not-a-package-manager", "random_user"
        expect(chatop_error).to include("didn't input a valid package name & manager")
        blocklist = Ingest::Blocklist.view(type: :packages)
        expect(blocklist).to be_empty
        Ingest::Blocklist.clear(type: :packages)
      end
    end

    context "blocklist remove" do
      it "removes from specific blocklist" do
        Ingest::Blocklist.clear(type: :packages)
        Ingest::Blocklist.add(type: :packages, item: "this_package:rubygems")
        chat "dg blocklist packages remove this_package rubygems", "random_user"
        expect(chatop_response).to include("Sucessfully removed")
        blocklist = Ingest::Blocklist.view(type: :packages)
        expect(blocklist).to_not include("this_package")
        Ingest::Blocklist.clear(type: :packages)
      end

      it "removes package arrays sucessfully" do
        Ingest::Blocklist.clear(type: :packages)
        chat "dg blocklist packages remove sarahsarah npm", "random_user"
        expect(chatop_response).to include("Sucessfully removed")
        blocklist = Ingest::Blocklist.view(type: :packages)
        expect(blocklist).to_not include("sarahsarah:npm")
        Ingest::Blocklist.clear(type: :packages)
      end

      it "ignores incorrect package array removals" do
        Ingest::Blocklist.clear(type: :packages)
        Ingest::Blocklist.add(type: :packages, item: "this_package:rubygems")
        chat "dg blocklist packages remove this_package 1234", "random_user"
        expect(chatop_error).to include("didn't input a valid package name & manager")
        Ingest::Blocklist.clear(type: :packages)
      end
    end

    context "checkpoint" do
      it "returns a checkpoint" do
        Checkpoint.create!(name: "my_checkpoint", last_checkpointed_id: 1234)
        chat "dg checkpoint my_checkpoint", "random_user"
        expect(chatop_response).to include("1234")
      end
      it "errors when a checkpoint doesn't exist" do
        chat "dg checkpoint thisdoesnotexist", "random_user"
        expect(chatop_error).to include("not found")
      end
    end

    context "checkpoints" do
      it "returns all checkpoints" do
        Checkpoint.create!(name: "my_checkpoint", last_checkpointed_id: 1234)
        Checkpoint.create!(name: "my_checkpoint2", last_checkpointed_id: 1234)
        chat "dg checkpoints", "random_user"
        expect(chatop_response).to include("my_checkpoint", "my_checkpoint2")
      end
    end

    context "packages" do
      it "returns info about packages" do
        factory.given_package("rake", "1")
        factory.given_package("rails", "3")

        # make sure rake is last updated
        get_package("rake").touch

        chat "dg packages rubygems", "random_user"
        expect(chatop_response).to include("count: 2", "Most recently updated: rake")
      end
      it "returns an error for unknown package manager" do
        chat "dg packages not_a_package_manager", "random_user"
        expect(chatop_error).to include("not_a_package_manager")
      end

      it "returns info about a specific package" do
        factory.given_package("rake", "1")

        chat "dg package rubygems rake", "random_user"
        expect(chatop_response).to include("name: \"rake\"")
      end

      it "overrides mapping for a specific package" do
        Repository.create!(github_repository_id: 1234, nwo: "rake/rake")
        rake = factory.given_package("rake", "1").package

        chat "dg package rubygems rake override rake/rake", "random_user"

        expect(rake.reload.github_repository_id).to eq(1234)
      end

      it "override returns an error if package does not already exist" do
        Repository.create!(github_repository_id: 1234, nwo: "bake/bake")

        chat "dg package rubygems bake override bake/bake", "random_user"
        expect(chatop_error).to eq("Package rubygems:bake not found. Use map if you want to map a completely unmapped package.")
      end

      it "allows mapping a previously unmapped package" do
        repo = Repository.create!(github_repository_id: 1234, nwo: "cake/cake")

        chat "dg package rubygems cake map cake/cake", "random_user"
        expect(chatop_response).to eq("Mapped rubygems:cake to cake/cake")
        new_package = Package.where(package_manager: 1, name: "cake").first
        expect(new_package).to be
        expect(new_package.repository_id).to eq(1234) # github_repository_id
        expect(new_package.repository_id_certainty).to eq(PackageToRepoMapping::Certainty::OVERRIDE)
      end

      it "allows the clearing of a mapped package" do
        Repository.create!(github_repository_id: 1234, nwo: "kofi/httparty")
        httparty = factory.given_package("httparty", "1").update_package(repository_id: 1234, repository_id_certainty: 70, package_manager: 1)

        expect(httparty.package.reload.repository_id).to eq(1234)
        expect(httparty.package.reload.repository_nwo).to eq("kofi/httparty")
        expect(httparty.package.reload.repository_id_certainty).to eq(PackageToRepoMapping::Certainty::CLEARLY_DEFINED_MATCH)

        chat "dg package rubygems clear_mapping httparty", "random_user"

        expect(chatop_response).to eq("Cleared Mapping for rubygems:httparty")
        expect(httparty.package.reload.repository_id).to be nil
        expect(httparty.package.reload.repository_nwo).to be nil
        expect(httparty.package.reload.repository_id_certainty).to eq(PackageToRepoMapping::Certainty::NULL)
      end

      it "map returns an error if package does already exist" do
        Repository.create!(github_repository_id: 1234, nwo: "pake/pake")
        pake = factory.given_package("pake", "1").package

        chat "dg package rubygems pake map pake/pake", "random_user"

        expect(chatop_error).to eq("Package rubygems:pake already mapped. Use override if you want to override the mapping")
      end
    end

    context "locks" do
      it "displays all job pod serializing locks in dg_locks table" do
        Lock.create!(lockname: "foo", holder: "foo-worker-abc123", expires: 10.minutes.from_now)
        Lock.create!(lockname: "bar", holder: "bar-worker-abc123", expires: 10.minutes.from_now)
        Lock.create!(lockname: "baz", holder: "baz-worker-abc123", expires: 10.minutes.from_now)

        chat "dg locks", "random_user"
        expect(chatop_response).to include("foo")
        expect(chatop_response).to include("bar")
        expect(chatop_response).to include("baz")
      end

      it "releases the named lock from it's holder in dg_locks table" do
        Lock.create!(lockname: "foo", holder: "foo-worker-abc123", expires: 10.minutes.from_now)
        Lock.create!(lockname: "bar", holder: "bar-worker-abc123", expires: 10.minutes.from_now)
        Lock.create!(lockname: "baz", holder: "baz-worker-abc123", expires: 10.minutes.from_now)

        chat "dg lock release bar", "random_user"
        expect(chatop_response).to eq("Released lock bar")
        expect(Lock.all.count).to eq(2)
        expect(Lock.where(lockname: "bar")).to be_empty
      end
    end

    context "explain" do
      it "explains queries" do
        chat "dg explain select id from dg_packages", "random_user"
        expect(chatop_response).to include("Table: dg_packages")
      end
      it "returns an error for bad queries" do
        chat "dg explain not a real sql", "random_user"
        expect(chatop_error).to include("You have an error in your SQL syntax")
      end
    end

    context "help" do
      it "outputs a list of known commands" do
        chat "dg help", "random_user"

        # Expect the length of our response to be the # of ChatOps we have +1 line for the header.
        expect(chatop_response.split("\n").length).to eq(ChatopsController.chatops.length + 1)
      end
    end

    context "dependency insights" do
      it "rebuilds for an org" do
        factory do
          org_repo = Repository.create!({
            github_repository_id: 10,
            github_owner_id: 20,
            nwo: "Anthophila/octokit"
          })

          PackageFactory.new("multi_xml", "0.5.2", :rubygems)
            .create!(published_at: "2018-10-10 20:33:33")
          PackageFactory.new("httparty", "2.0.1", :rubygems)
            .create!(published_at: "2018-09-05 20:33:33")

          given_manifest(
            github_repo_id: 10,
            manifest_type:  :gemfile_lock,
            package_manager: :rubygems,
            filename:       "Gemfile.lock",
            path:           "/",
            revision:       1,
            dependencies:   [
              {
                package_name: "multi_xml",
                requirements: "= 0.5.2",
              },
              {
                package_name: "httparty",
                requirements: "= 2.0.1",
              },
            ]
          )
        end

        expect(Views::PackageReleaseDependentCount.where(github_owner_id: 20).count).to eq(0)

        chat "dg insights rebuild 20", "random_user"
        expect(chatop_response).to include("Rebuilt dependent counts for org: 20")

        expect(Views::PackageReleaseDependentCount.where(github_owner_id: 20).count).to eq(2)
      end
    end

    context "audit github owner" do
      before do
        repo = factory.given_repository(github_owner_id: 1)
        2.times do
          factory.given_manifest(github_repo_id: repo.github_repository_id)
        end
      end

      it "outputs the count of objects for the owner" do
        chat "dg audit github owner 1", "random_user"

        expect(chatop_response).to include("Repositories: 1")
        expect(chatop_response).to include("Manifests: 2")
        expect(chatop_response).to include("Backfill: nil")
      end
    end

    shared_examples "audit abstract repo dependencies" do |normalized_tables|
      before do
        allow(DependencyGraph).to receive(:use_normalized_tables?).and_return(normalized_tables)
      end

      it "audits and deletes successfully" do
        repo = Repository.create!(github_repository_id: 1234)

        AbstractRepositoryDependency.create!({
          repository_id:   repo.id,
          package_manager: Types::PackageManager[:rubygems],
          package_name:    "rails",
        })

        AbstractRepositoryDependency.create!({
          repository_id:   repo.id,
          package_manager: Types::PackageManager[:rubygems],
          package_name:    "rake",
        })

        manifest = Manifest.create!({
          repository_id: repo.id,
          package_manager: Types::PackageManager[:rubygems],
          manifest_type:   Types::Manifest[:gemfile],
          filename:        "Gemfile.lock",
          path:            "",
          latest_git_ref:  "77dab21",
          last_pushed_at:  Time.now,
        })

        manifest.dependencies.create!({
          package_name:          "rake",
          package_manager:       Types::PackageManager[:rubygems],
          requirements:          "~> 4.2.0",
          scope:                 :runtime,
          last_seen_at_revision: 0,
        })

        chat "dg audit abstract repo dependencies rubygems rails", "random_user"
        expect(chatop_response).to include("1 orphan dependency deleted")

        chat "dg audit abstract repo dependencies rubygems rake", "random_user"
        expect(chatop_response).to include("0 orphan dependencies deleted")
      end

      it "errors gracefully" do
        chat "dg audit abstract repo dependencies notapackagemanager rails", "random_user"
        expect(chatop_error).to include("Could not find Types::PackageManager")
      end
    end

    context "normalized tables" do
      it_should_behave_like "audit abstract repo dependencies", true
    end

    context "denormalized tables" do
      it_should_behave_like "audit abstract repo dependencies", false
    end

    context "imports packages from registry", vcr: { cassette_name: "npm-one-off" } do
      it "pulls and downloads a package successfully" do
        chat "dg package import npm react", "random_user"
        expect(chatop_response).to include("Imported 212 releases of *react*")
      end

      it "errors gracefully if invalid/unsupported registry is passed" do
        chat "dg package import fake_registry react", "random_user"
        expect(chatop_error).to include("Unimplemented or Invalid Registry")
      end
    end

    context "importing actions packages" do
      it "successfully imports a package" do
        allow_any_instance_of(BlobOperations::Spokes::Client).to receive(:object_exists?).and_return(true)
        repo = Repository.create!(github_repository_id: 1234, nwo: "actions/checkout")

        perform_enqueued_jobs do
          chat "dg package import actions actions/checkout 3.0.0", "random_user"
        end

        release = PackageRelease.find_by(package_name: "actions/checkout", name: "3.0.0")
        expect(release).to_not be_nil
      end
    end

    context "imports license data from ClearlyDefined" do
      before do
        # Stub out the call RepositoryFinder mixin used in the ClearlyDefined class
        allow_any_instance_of(ClearlyDefined).to receive(:get_gh_repo_id).and_return(1234)
      end

      it "pulls and downloads a package successfully when a version is specified", vcr: { cassette_name: "cd-import-package-one-version" } do
        factory.given_package "console-browserify", "1.2.0", Types::PackageManager[:npm]

        chat "dg clearly_defined import npm console-browserify 1.2.0", "random_user"
        expect(chatop_response).to eq((<<~eos
          Imported license and attribution data for `npm:console-browserify` from ClearlyDefined:
          ```
          console-browserify@1.2.0: <empty> (0 attributions) -> MIT (1 attributions)
          ```
          eos
        ).strip)
      end

      it "pulls and downloads a package successfully for all versions", vcr: { cassette_name: "cd-import-package-two-versions" } do
        factory.given_package "console-browserify", "1.1.0", Types::PackageManager[:npm]
        factory.given_package "console-browserify", "1.2.0", Types::PackageManager[:npm]

        chat "dg clearly_defined import npm console-browserify", "random_user"
        expect(chatop_response).to eq((<<~eos
          Imported license and attribution data for `npm:console-browserify` from ClearlyDefined:
          ```
          console-browserify@1.1.0: <empty> (0 attributions) -> MIT (1 attributions)
          console-browserify@1.2.0: <empty> (0 attributions) -> MIT (1 attributions)
          ```
          eos
        ).strip)
      end

      it "pulls and downloads a golang package successfully", vcr: { cassette_name: "cd-import-golang-package" } do
        factory.given_package "golang.org/x/crypto", "v0.0.0-20210921155107-089bfa567519", Types::PackageManager[:go]

        chat "dg clearly_defined import go golang.org/x/crypto v0.0.0-20210921155107-089bfa567519", "random_user"
        expect(chatop_response).to eq((<<~eos
          Imported license and attribution data for `go:golang.org/x/crypto` from ClearlyDefined:
          ```
          golang.org/x/crypto@v0.0.0-20210921155107-089bfa567519: <empty> (0 attributions) -> BSD-3-Clause AND OTHER (17 attributions)
          ```
          eos
        ).strip)
      end

      it "pulls and downloads a rubygems package with attributions successfully", vcr: { cassette_name: "cd-import-rubygems-nokogiri" } do
        factory.given_package "nokogiri", "1.16.5", Types::PackageManager[:rubygems]

        chat "dg clearly_defined import rubygems nokogiri 1.16.5", "random_user"
        expect(chatop_response).to eq((<<~eos
          Imported license and attribution data for `rubygems:nokogiri` from ClearlyDefined:
          ```
          nokogiri@1.16.5: <empty> (0 attributions) -> MIT (19 attributions)
          ```
          eos
        ).strip)
      end

      it "fails with a message when the package manager is invalid" do
        chat "dg clearly_defined import not-a-real-package-manager rails", "random_user"
        expect(chatop_error).to include("Invalid package manager. Must be one of: rubygems, npm, pip, maven, nuget, composer, go, rust")
      end

      it "fails with a message when the package can't be found" do
        chat "dg clearly_defined import npm console-browserify 1.2.0", "random_user"
        expect(chatop_error).to include("Could not find local package: `npm:console-browserify@1.2.0`")
      end
    end
  end
end
