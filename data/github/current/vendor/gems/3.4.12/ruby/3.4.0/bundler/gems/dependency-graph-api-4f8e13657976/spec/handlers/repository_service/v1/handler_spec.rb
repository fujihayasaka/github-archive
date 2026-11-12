require "rails_helper"

describe RepositoryService::V1::Handler do
  let(:handler) { RepositoryService::V1::Handler.new }

  describe "get_direct_dependencies" do
    before do
      factory do
        # direct, Pip-managed dependencies of the input repository
        Repository.create!({
          github_repository_id: 11,
          nwo: "django/django"
        })
        Repository.create!({
          github_repository_id: 13,
          nwo: "numpy/numpy"
        })

        # duplicate packages are defined against this repo
        Repository.create!({
          github_repository_id: 15,
          nwo: "someorg/twinsies",
        })

        # transitive, Pip-managed dependency of the input repository
        Repository.create!({
          github_repository_id: 12,
          nwo: "requests/requests"
        })

        # direct but NOT Pip-managed dependency of the input repository
        Repository.create!({
          github_repository_id: 14,
          nwo: "kelektiv/node.bcrypt.js"
        })

        django = given_package("django", "4.2.1", :pip, repository_id: 11)
          .dependency("requests", "1.2.1").package
        given_package("requests", "1.2.1", :pip, repository_id: 12)
        given_package("numpy", "1.21.0", :pip, repository_id: 13)
        given_package("bcrypt", "5.0.1", :npm, repository_id: 14)
        # two packages mapping to same source repository:
        given_package("foo", "0.1.0", :pip, repository_id: 15)
        given_package("bar", "0.2.0", :pip, repository_id: 15)
        # a package with a nil repository id
        given_package("sherlock", "1.0.0", :pip, repository_id: nil)
        given_manifest(
          github_repo_id: 100,
          package_manager: :pip,
          manifest_type:  :requirements_txt,
          filename:       "requirements.txt",
          path:           "/",
          dependencies:   [
            {
              package_name: "django",
              requirements: "= 4.2.1",
            },
            {
              package_name: "numpy",
              requirements: "= 1.21.0",
            },
            {
              package_name: "foo",
              requirements: "= 0.1.0",
            },
            {
              package_name: "bar",
              requirements: "= 0.2.0",
            },
          ]
        )
        given_manifest(
          github_repo_id: 100,
          package_manager: :npm,
          manifest_type:  :package_json,
          filename:       "package.json",
          path:           "/",
          dependencies:   [
            {
              package_name: "bcrypt",
              requirements: "= 5.0.1",
            }
          ]
        )
      end
    end

    # convenience definitions
    let(:nonexistent_repository_id) { 333 }
    let(:input_repository_id) { 100 } # valid repo, for our purposes
    let(:expected_dependency_repository_ids) { [11, 13, 15] }
    let(:transitive_repository_id) { 12 }
    let(:not_pip_managed_repository_id) { 14 }

    it "returns a 4xx Twirp error if no repository ID is supplied" do
      req = DependencyGraphAPI::V1::GetDirectDependenciesRequest.new({
        repository_id: nonexistent_repository_id
      })

      resp = handler.get_direct_dependencies(req, {})
      expect(resp.code).to eq(:not_found)
    end

    it "returns a 4xx Twirp error if no repository ID is supplied" do
      req = DependencyGraphAPI::V1::GetDirectDependenciesRequest.new({
        repository_id: nil
      })

      resp = handler.get_direct_dependencies(req, {})
      expect(resp.code).to eq(:invalid_argument)
    end

    it "returns a 4xx Twirp error if an invalid package_mamagers filter is supplied" do
      req = DependencyGraphAPI::V1::GetDirectDependenciesRequest.new({
        repository_id: input_repository_id,
        package_managers: [-123]
      })

      resp = handler.get_direct_dependencies(req, {})
      expect(resp.code).to eq(:bad_request)
    end

    it "returns the repository IDs of all direct, Pip-managed dependencies of the input repository" do
      req = DependencyGraphAPI::V1::GetDirectDependenciesRequest.new({
        repository_id: input_repository_id,
        package_managers: [
          DependencyGraphAPI::V1::PackageManager::PACKAGE_MANAGER_PIP,
        ]
      })

      resp = handler.get_direct_dependencies(req, {})
      got_repo_ids = resp.repository_ids

      # direct dependencies of the subject repo will be listed
      expect(got_repo_ids).to eq(expected_dependency_repository_ids)

      # repository IDs hosting multiple packages should be deduped
      expect(got_repo_ids.count(15)).to eq(1)

      # transitive dependencies are never returned from this API
      expect(got_repo_ids).not_to include(not_pip_managed_repository_id)
      expect(got_repo_ids).not_to include(transitive_repository_id)
    end

    it "returns the repository IDs of all direct dependencies matching the package_managers filter for the input repository" do
      req = DependencyGraphAPI::V1::GetDirectDependenciesRequest.new({
        repository_id: input_repository_id,
        package_managers: [
          DependencyGraphAPI::V1::PackageManager::PACKAGE_MANAGER_NPM,
        ]
      })

      resp = handler.get_direct_dependencies(req, {})
      got_repo_ids = resp.repository_ids

      # only direct NPM dependencies of the subject repo will be listed
      expect(got_repo_ids.count).to eq(1)
      expect(got_repo_ids.first).to eq(not_pip_managed_repository_id)
      expect(got_repo_ids).not_to include(expected_dependency_repository_ids)

      # transitive dependencies are never returned from this API
      expect(got_repo_ids).not_to include(transitive_repository_id)
    end

    it "returns the repository IDs of all direct dependencies of the input repository when PM filter is unspecified" do
      req = DependencyGraphAPI::V1::GetDirectDependenciesRequest.new({
        repository_id: input_repository_id,
      })

      resp = handler.get_direct_dependencies(req, {})
      got_repo_ids = resp.repository_ids

      # direct dependencies of the subject repo will be listed
      expected = expected_dependency_repository_ids + [not_pip_managed_repository_id]
      expect(got_repo_ids).to match_array(expected)

      # repository IDs hosting multiple packages should be deduped
      expect(got_repo_ids.count(15)).to eq(1)

      # transitive dependencies are never returned from this API
      expect(got_repo_ids).not_to include(transitive_repository_id)
    end

    it "returns the repository IDs of direct dependencies eligible for inclusion by multi-entry PM filter" do
      req = DependencyGraphAPI::V1::GetDirectDependenciesRequest.new({
        repository_id: input_repository_id,
        package_managers: [
          DependencyGraphAPI::V1::PackageManager::PACKAGE_MANAGER_PIP,
          DependencyGraphAPI::V1::PackageManager::PACKAGE_MANAGER_NPM,
        ]
      })

      resp = handler.get_direct_dependencies(req, {})
      got_repo_ids = resp.repository_ids

      # direct dependencies of the subject repo will be listed
      expected = expected_dependency_repository_ids + [not_pip_managed_repository_id]
      expect(got_repo_ids).to match_array(expected)

      # repository IDs hosting multiple packages should be deduped
      expect(got_repo_ids.count(15)).to eq(1)

      # transitive dependencies are never returned from this API
      expect(got_repo_ids).not_to include(transitive_repository_id)
    end


  end
end
