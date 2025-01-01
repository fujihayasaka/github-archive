require "rails_helper"
require "dependency_graph/sbom/spdx/generator"

shared_examples "an sbom generator" do
  let(:test_repository_name) { "mmcfly/power_of_love" }
  let(:test_namespace_base) { "https://github.com/" }

  let(:empty_response) do
    Twirp::ClientResp.new(data: Github::DependencySnapshotsApi::GetDependenciesForRepositoryResponse.new(manifests: {}, all_manifests: []))
  end

  let(:one_manifest_and_dependency) do
    Twirp::ClientResp.new(data: Github::DependencySnapshotsApi::GetDependenciesForRepositoryResponse.new(
      manifests: {
        "first entry for same package-lock": Github::DependencySnapshotsApi::Manifest.new(
          file_path: "/some/path/package-lock.json",
          dependencies: {
            "@actions/http-client": Github::DependencySnapshotsApi::Manifest::Dependency.new(
              package_url: "pkg:/npm/%40actions/http-client@1.0.6",
              dependencies: ["tunnel"]
            )
          }
        ),
      },
      all_manifests: [
        Github::DependencySnapshotsApi::Manifest.new(
          snapshot_id: 1,
          file_path: "/some/path/package-lock.json",
          name: "first entry for same package-lock",
          dependencies: {
            "@actions/http-client": Github::DependencySnapshotsApi::Manifest::Dependency.new(
              package_url: "pkg:/npm/%40actions/http-client@1.0.6",
              dependencies: ["tunnel"]
            )
          }
        )
      ],
      snapshots: {
        1 => Github::DependencySnapshotsApi::GetDependenciesForRepositoryResponse::Snapshot.new(
          detector: Github::DependencySnapshotsApi::GetDependenciesForRepositoryResponse::Snapshot::DetectorMetadata.new(
            name: "test detector"
          )
        )
      }
    ))
  end

  let(:one_manifest_and_dependency_with_names_with_restricted_characters) do
    Twirp::ClientResp.new(data: Github::DependencySnapshotsApi::GetDependenciesForRepositoryResponse.new(
      manifests: {
        "first entry for some pom file": Github::DependencySnapshotsApi::Manifest.new(
          file_path: "/some/path/pom.xml",
          dependencies: {
            "org.apache.xmlgraphics:batik-anim": Github::DependencySnapshotsApi::Manifest::Dependency.new(
              package_url: "pkg:maven/org.apache.xmlgraphics/batik-anim@1.9.1",
              dependencies: []
            )
          }
        ),
      },
      all_manifests: [
        Github::DependencySnapshotsApi::Manifest.new(
          snapshot_id: 1,
          file_path: "/some/path/pom.xml",
          name: "first entry for some package-lock",
          dependencies: {
            "org.apache.xmlgraphics:batik-anim": Github::DependencySnapshotsApi::Manifest::Dependency.new(
              package_url: "pkg:maven/org.apache.xmlgraphics/batik-anim@1.9.1",
              dependencies: []
            )
          }
        )
      ],
      snapshots: {
        1 => Github::DependencySnapshotsApi::GetDependenciesForRepositoryResponse::Snapshot.new(
          detector: Github::DependencySnapshotsApi::GetDependenciesForRepositoryResponse::Snapshot::DetectorMetadata.new(
            name: "test detector"
          )
        )
      }
    ))
  end

  let(:snapshots_client) { double(DependencyGraphAPI::DependencySnapshotsAPI::DependenciesClient) }
  let(:features_client) { double(Monolith::Features) }
  let(:generator) { described_class.new(snapshot_dependencies_client: snapshots_client, features_client: features_client) }

  before :each do
    allow(snapshots_client).to receive(:get_dependencies_for_repository).and_return(empty_response)
    allow(Instrument).to receive(:count)
  end

  it "generates an object that describes an SPDX document for a repository" do
    package_one = factory.given_package("httparty", "2.0.1", :rubygems).package
    release = package_one.releases.first
    release.update!(license: "MIT")

    Attribution.create!(package_release: release, attribution: "Copyright 1985 Marty McFly")
    Attribution.create!(package_release: release, attribution: "Copyright 2015 Marty McFly Jr.")

    package_two = factory.given_package("rails", "5.0.1", :rubygems).package
    release_two = package_two.releases.first
    release_two.update!(license: "")

    factory.given_manifest(
      github_repo_id: 10,
      manifest_type:  :gemfile,
      package_manager: :rubygems,
      filename:       "Gemfile",
      path:           "/",
      revision:       1,
      dependencies:   [
        {
          package_name: "multi_xml",
          requirements: "> 0.5.2, <= 1.0",
        },
        {
          package_name: "httparty",
          requirements: "= 2.0.1",
        },
        {
          package_name: "rails",
          requirements: "= 5.0.1"
        }
      ]
    )

    # Ensure we are getting data back from the snapshots client
    allow(snapshots_client).to receive(:get_dependencies_for_repository).and_return(one_manifest_and_dependency)

    spdx = generator.generate(repository_id: 10, repository_name: test_repository_name, namespace_base: test_namespace_base)
    expect(spdx[:creationInfo][:creators].sort).to eq([
      "Tool: GitHub.com-Dependency-Graph",
      "Tool: test detector"
    ])
    expect(spdx[:documentDescribes]).to eq(["SPDXRef-com.github.mmcfly-power-of-love"])
    expect(spdx[:documentNamespace]).to match(%r{https://github.com/mmcfly/power_of_love/dependency_graph/sbom-[A-Za-z0-9]{16}})

    # Ensure instrumentation is working as expected
    expect(Instrument).to have_received(:count).with("sbom.dependencies.count", 3, { dependency_source: :database })
    expect(Instrument).to have_received(:count).with("sbom.dependencies.count", 1, { dependency_source: :snapshots })
    expect(Instrument).to have_received(:count).with("sbom.unique_dependencies.count", 4)

    packages = spdx[:packages]

    expect(packages).to contain_exactly(
      {
        "SPDXID": "SPDXRef-com.github.mmcfly-power-of-love",
        "name": "com.github.mmcfly/power_of_love",
        "versionInfo": "",
        "downloadLocation": "git+https://github.com/mmcfly/power_of_love",
        "filesAnalyzed": false,
        "supplier": "NOASSERTION",
        "externalRefs": [{
          "referenceCategory": "PACKAGE-MANAGER",
          "referenceType": "purl",
          "referenceLocator": "pkg:github/mmcfly/power_of_love"
        }]
      }, {
        "SPDXID": "SPDXRef-rubygems-httparty-2.0.1",
        "name": "rubygems:httparty",
        "versionInfo": "2.0.1",
        "downloadLocation": "NOASSERTION",
        "filesAnalyzed": false,
        "licenseConcluded": "MIT",
        "supplier": "NOASSERTION",
        "externalRefs": [{
          "referenceCategory": "PACKAGE-MANAGER",
          "referenceType": "purl",
          "referenceLocator": "pkg:gem/httparty@2.0.1"
        }],
        "copyrightText": "Copyright 1985 Marty McFly, Copyright 2015 Marty McFly Jr."
      }, {
        "SPDXID": "SPDXRef-rubygems-multi-xml",
        "name": "rubygems:multi_xml",
        "versionInfo": "> 0.5.2,<= 1.0",
        "downloadLocation": "NOASSERTION",
        "filesAnalyzed": false,
        "supplier": "NOASSERTION",
        "externalRefs": [{
          "referenceCategory": "PACKAGE-MANAGER",
          "referenceType": "purl",
          "referenceLocator": "pkg:gem/multi_xml"
        }]
      }, {
        "SPDXID": "SPDXRef-rubygems-rails-5.0.1",
        "name": "rubygems:rails",
        "versionInfo": "5.0.1",
        "downloadLocation": "NOASSERTION",
        "filesAnalyzed": false,
        "supplier": "NOASSERTION",
        "externalRefs": [{
          "referenceCategory": "PACKAGE-MANAGER",
          "referenceType": "purl",
          "referenceLocator": "pkg:gem/rails@5.0.1"
        }]
      }, {
        "SPDXID": "SPDXRef-npm-actions-http-client-1.0.6",
        "downloadLocation": "NOASSERTION",
        "filesAnalyzed": false,
        "name": "npm:@actions/http-client",
        "supplier": "NOASSERTION",
        "versionInfo": "1.0.6",
        "externalRefs": [{
          "referenceCategory": "PACKAGE-MANAGER",
          "referenceType": "purl",
          "referenceLocator": "pkg:npm/%40actions/http-client@1.0.6"
        }]
      }
    )
  end

  it "packages without an exact version specified will not use the version in their name" do
    factory.given_manifest(
      github_repo_id: 10,
      manifest_type:  :gemfile,
      package_manager: :rubygems,
      filename:       "Gemfile",
      path:           "/",
      revision:       1,
      dependencies:   [
        {
          package_name: "multi_xml",
          requirements: "> 0.5.2, <= 1.0",
        },
      ]
    )

    spdx = generator.generate(repository_id: 10, repository_name: test_repository_name, namespace_base: test_namespace_base)
    # The first package listed is always the package for the SPDX Document which doesn't include a version
    package = spdx[:packages].second

    expect(package[:SPDXID]).to eq("SPDXRef-rubygems-multi-xml")
    expect(package[:name]).to eq("rubygems:multi_xml")
    expect(package[:versionInfo]).to eq("> 0.5.2,<= 1.0")
  end

  it "duplicate packages in different manifests will resolve to a single package" do
    factory.given_manifest(
      github_repo_id: 10,
      manifest_type:  :gemfile,
      package_manager: :rubygems,
      filename:       "Gemfile.lock",
      path:           "/first-project/",
      revision:       1,
      dependencies:   [
        {
          package_name: "multi_xml",
          requirements: "= 1.0",
        },
      ]
    )

    factory.given_manifest(
      github_repo_id: 10,
      manifest_type:  :gemfile,
      package_manager: :rubygems,
      filename:       "Gemfile",
      path:           "/second-project/",
      revision:       1,
      dependencies:   [
        {
          package_name: "rails",
          requirements: "~> 6.0",
        },
        {
          package_name: "multi_xml",
          requirements: "= 1.0",
        },
      ]
    )

    spdx = generator.generate(repository_id: 10, repository_name: test_repository_name, namespace_base: test_namespace_base)
    expect(spdx[:packages].count).to eq(3)
  end

  # Potential bug or non-desirable behavior! This test is here to document something that we probably
  # don't want to happen, but some more work needs to be done to determine the correct behavior.
  it "non-overlapping version ranges resolve to the same package" do
    factory.given_manifest(
      github_repo_id: 10,
      manifest_type:  :gemfile,
      package_manager: :rubygems,
      filename:       "Gemfile",
      path:           "/first-project/",
      revision:       1,
      dependencies:   [
        {
          package_name: "multi_xml",
          requirements: "~> 2.0",
        },
      ]
    )

    factory.given_manifest(
      github_repo_id: 10,
      manifest_type:  :gemfile,
      package_manager: :rubygems,
      filename:       "Gemfile",
      path:           "/second-project/",
      revision:       1,
      dependencies:   [
        {
          package_name: "multi_xml",
          requirements: "< 1.0",
        },
      ]
    )

    spdx = generator.generate(repository_id: 10, repository_name: test_repository_name, namespace_base: test_namespace_base)
    expect(spdx[:packages].count).to eq(2)

    # Since only the first package encountered is kept, the version range from that package should be
    # present, and the second should be dropped.
    # This is not necessarily _correct_ or _desired_ behavior but it is the current behavior.
    expect(spdx[:packages].second[:versionInfo]).to eq("~> 2.0")
  end

  it "lockfile requirements are correctly extracted by fast-path" do
    factory.given_manifest(
      github_repo_id: 10,
      manifest_type:  :gemfile_lock,
      package_manager: :rubygems,
      filename:       "Gemfile.lock",
      path:           "/first-project/",
      revision:       1,
      dependencies:   [
        {
          package_name: "multi_xml",
          requirements: "= 2.0",
        },
      ]
    )

    spdx = generator.generate(repository_id: 10, repository_name: test_repository_name, namespace_base: test_namespace_base)
    expect(spdx[:packages].count).to eq(2)
    expect(spdx[:packages].second[:versionInfo]).to eq("2.0")
  end

  it "does not include an externalRef section with a PURL for a package if no exact version is given" do
    factory.given_manifest(
      github_repo_id: 10,
      manifest_type:  :gemfile,
      package_manager: :rubygems,
      filename:       "Gemfile",
      path:           "/first-project/",
      revision:       1,
      dependencies:   [
        {
          package_name: "multi_xml",
          requirements: "~> 2.0",
        },
      ]
    )

    spdx = generator.generate(repository_id: 10, repository_name: test_repository_name, namespace_base: test_namespace_base)
    expect(spdx[:packages].count).to eq(2)
    expect(spdx[:packages].second[:versionInfo]).to eq("~> 2.0")
    expect(spdx[:packages].second.key?(:externalRefs)).to be true
    expect(spdx[:packages].second[:externalRefs].first[:referenceLocator]).to eq("pkg:gem/multi_xml")
  end

  it "generates an sbom when a repository only has snapshots" do
    expect(Repository.find_by(github_repository_id: 666)).to be_nil
    expect(Manifest.count).to eq(0)

    # Ensure we are getting data back from the snapshots client
    allow(snapshots_client).to receive(:get_dependencies_for_repository).and_return(one_manifest_and_dependency)

    spdx = generator.generate(repository_id: 666, repository_name: "docbrown/delorean", namespace_base: test_namespace_base)
    expect(spdx[:creationInfo][:creators].sort).to eq([
      "Tool: GitHub.com-Dependency-Graph",
      "Tool: test detector"
    ])
    expect(spdx[:documentDescribes]).to eq(["SPDXRef-com.github.docbrown-delorean"])
    expect(spdx[:documentNamespace]).to match(%r{https://github.com/docbrown/delorean/dependency_graph/sbom-[A-Za-z0-9]{16}})

    packages = spdx[:packages]

    expect(packages).to eq([
      {
        "SPDXID": "SPDXRef-com.github.docbrown-delorean",
        "name": "com.github.docbrown/delorean",
        "versionInfo": "",
        "downloadLocation": "git+https://github.com/docbrown/delorean",
        "filesAnalyzed": false,
        "supplier": "NOASSERTION",
        "externalRefs": [{
          "referenceCategory": "PACKAGE-MANAGER",
          "referenceType": "purl",
          "referenceLocator": "pkg:github/docbrown/delorean"
        }]
      }, {
        "SPDXID": "SPDXRef-npm-actions-http-client-1.0.6",
        "downloadLocation": "NOASSERTION",
        "filesAnalyzed": false,
        "name": "npm:@actions/http-client",
        "supplier": "NOASSERTION",
        "versionInfo": "1.0.6",
        "externalRefs": [{
          "referenceCategory": "PACKAGE-MANAGER",
          "referenceType": "purl",
          "referenceLocator": "pkg:npm/%40actions/http-client@1.0.6"
        }]
      }
    ])
  end

  it "generates SPDXID's with legal characters only" do
    expect(Repository.find_by(github_repository_id: 123)).to be_nil
    expect(Manifest.count).to eq(0)

    # Ensure we are getting data back from the snapshots client
    allow(snapshots_client).to receive(:get_dependencies_for_repository).and_return(one_manifest_and_dependency_with_names_with_restricted_characters)

    spdx = generator.generate(repository_id: 123, repository_name: "docbrown/delorean", namespace_base: test_namespace_base)

    packages = spdx[:packages]

    expect(packages).to eq([
      {
        "SPDXID": "SPDXRef-com.github.docbrown-delorean",
        "downloadLocation": "git+https://github.com/docbrown/delorean",
        "filesAnalyzed": false,
        "name": "com.github.docbrown/delorean",
        "supplier": "NOASSERTION",
        "versionInfo": "",
        "externalRefs": [{
          "referenceCategory": "PACKAGE-MANAGER",
          "referenceType": "purl",
          "referenceLocator": "pkg:github/docbrown/delorean"
        }]
      }, {
        "SPDXID": "SPDXRef-maven-org.apache.xmlgraphics-batik-anim-1.9.1",
        "downloadLocation": "NOASSERTION",
        "filesAnalyzed": false,
        "name": "maven:org.apache.xmlgraphics:batik-anim",
        "supplier": "NOASSERTION",
        "versionInfo": "1.9.1",
        "externalRefs": [{
          "referenceCategory": "PACKAGE-MANAGER",
          "referenceType": "purl",
          "referenceLocator": "pkg:maven/org.apache.xmlgraphics/batik-anim@1.9.1"
        }]
      }
    ])
  end

  it "does not include manifest if lockfile supersedes it" do
    factory.given_manifest(
      github_repo_id: 10,
      manifest_type:  :gemfile,
      package_manager: :rubygems,
      filename:       "Gemfile",
      path:           "/",
      revision:       1,
      dependencies:   [
        {
          package_name: "rails",
          requirements: "> 1.0.0",
        },
      ]
    )

    factory.given_manifest(
      github_repo_id: 10,
      manifest_type:  :gemfile_lock,
      package_manager: :rubygems,
      filename:       "Gemfile.lock",
      path:           "/",
      revision:       1,
      dependencies:   [
        {
          package_name: "rails",
          requirements: "= 5.0.0",
        },
      ]
    )

    spdx = generator.generate(repository_id: 10, repository_name: test_repository_name, namespace_base: test_namespace_base)

    expect(spdx[:packages].length).to eq(2)

    # The first package listed is always the package for the SPDX Document which doesn't include a version
    expect(spdx[:packages].second).to include({
      SPDXID: "SPDXRef-rubygems-rails-5.0.0",
      name: "rubygems:rails",
      versionInfo: "5.0.0"
    })
  end

  it "top-level packges includes downloadLocation" do
    spdx = generator.generate(repository_id: 10, repository_name: test_repository_name, namespace_base: test_namespace_base)

    expect(spdx[:packages].first).to include({
      downloadLocation: "git+https://github.com/mmcfly/power_of_love"
    })
  end

  it "top-level package includes repository license" do
    spdx = generator.generate(
      repository_id: 10,
      repository_name: test_repository_name,
      namespace_base: test_namespace_base,
      repository_license: "MIT"
    )

    expect(spdx[:packages].first).to include({
      licenseDeclared: "MIT"
    })
    expect(spdx[:packages].first).not_to include(:licenseConcluded)
  end

  it "includes relationships" do
    factory.given_manifest(
      github_repo_id: 10,
      manifest_type:  :gemfile,
      package_manager: :rubygems,
      filename:       "Gemfile",
      path:           "/",
      revision:       1,
      dependencies:   [
        {
          package_name: "multi_xml",
          requirements: "> 0.5.2, <= 1.0",
        },
        {
          package_name: "httparty",
          requirements: "= 2.0.1",
        },
        {
          package_name: "rails",
          requirements: "= 5.0.1"
        }
      ]
    )

    allow(snapshots_client).to receive(:get_dependencies_for_repository).and_return(one_manifest_and_dependency)

    spdx = generator.generate(repository_id: 10, repository_name: test_repository_name, namespace_base: test_namespace_base)

    expect(spdx[:relationships]).to match_array([
      { relatedSpdxElement: "SPDXRef-rubygems-httparty-2.0.1",
        relationshipType: "DEPENDS_ON",
        spdxElementId: "SPDXRef-com.github.mmcfly-power-of-love" },
      { relatedSpdxElement: "SPDXRef-rubygems-multi-xml",
        relationshipType: "DEPENDS_ON",
        spdxElementId: "SPDXRef-com.github.mmcfly-power-of-love" },
      { relatedSpdxElement: "SPDXRef-rubygems-rails-5.0.1",
        relationshipType: "DEPENDS_ON",
        spdxElementId: "SPDXRef-com.github.mmcfly-power-of-love" },
      { relatedSpdxElement: "SPDXRef-npm-actions-http-client-1.0.6",
        relationshipType: "DEPENDS_ON",
        spdxElementId: "SPDXRef-com.github.mmcfly-power-of-love" }
    ])
  end

  it "does not include nil values for licenseDeclared and licenseConcluded" do
    factory.given_manifest(
      github_repo_id: 10,
      manifest_type:  :gemfile,
      package_manager: :rubygems,
      filename:       "Gemfile",
      path:           "/",
      revision:       1,
      dependencies:   [
        {
          package_name: "multi_xml",
          requirements: "> 0.5.2, <= 1.0",
        }
      ]
    )

    spdx = generator.generate(repository_id: 10, repository_name: test_repository_name, namespace_base: test_namespace_base)

    expect(spdx[:packages][0]).not_to include(:licenseDeclared, :licenseConcluded)
    expect(spdx[:packages][1]).not_to include(:licenseDeclared, :licenseConcluded)
  end

  it "does not include NOASSERTION for licenseDeclared and licenseConcluded" do
    factory do
      given_package("github.com/golang/protobuf", "1.5.3", :go).update_package_release({ license: "NOASSERTION" })

      given_manifest(
        github_repo_id: 123,
        manifest_type:  :go_mod,
        package_manager: :go,
        filename:       "go.mod",
        path:           "/",
        revision:       2,
        dependencies:   [
          {
            package_name: "github.com/golang/protobuf",
            requirements: "= 1.5.3",
          }
        ]
      )

    end

    spdx = generator.generate(
      repository_id: 123,
      repository_name: test_repository_name,
      namespace_base: test_namespace_base,
      repository_license: "NOASSERTION"
    )

    expect(spdx[:packages][0]).not_to include(:licenseDeclared)
    expect(spdx[:packages][1]).not_to include(:licenseConcluded)
  end

  it "excludes licenseDeclared and licenseConcluded unless they are valid SPDX Ids " do
    factory do
      given_package("react", "17.0.1", :npm).update_package_release({ license: "Some invalid ID" })
      given_package("jest", "29.6.4", :npm).update_package_release({ license: "MIT" })

      given_manifest(
        github_repo_id: 123,
        manifest_type:  :package_json,
        package_manager: :npm,
        filename:       "Package.json",
        path:           "/",
        revision:       3,
        dependencies:   [
          {
            package_name: "react",
            requirements: "= 17.0.1",
          },
          {
            package_name: "jest",
            requirements: "= 29.6.4",
          }
        ]
      )

    end

    spdx = generator.generate(
      repository_id: 123,
      repository_name: test_repository_name,
      namespace_base: test_namespace_base,
      repository_license: "Lorem Ipsum"
    )

    # invalid SPDX Ids
    expect(spdx[:packages][0]).not_to include(:licenseDeclared)
    expect(spdx[:packages].find { |package| package[:name] == "npm:react" }).not_to include(:licenseConcluded)

    # valid SPDX Id
    expect(spdx[:packages].find { |package| package[:name] == "npm:jest" }).to include(:licenseConcluded)
  end


  it "includes a creator comment if exact versions cannot be resolved for all dependencies" do
    factory.given_manifest(
      github_repo_id: 10,
      manifest_type:  :gemfile,
      package_manager: :rubygems,
      filename:       "Gemfile",
      path:           "/",
      revision:       1,
      dependencies:   [
        {
          package_name: "multi_xml",
          requirements: "> 0.5.2, <= 1.0",
        },
        {
          package_name: "httparty",
          requirements: "= 2.0.1",
        }
      ]
    )

    spdx = generator.generate(repository_id: 10, repository_name: test_repository_name, namespace_base: test_namespace_base)

    expect(spdx[:creationInfo][:comment]).to match(/^Exact versions could not be resolved/)
  end

  it "does not include a creator comment if exact versions can be resolved for all dependencies" do
    factory.given_manifest(
      github_repo_id: 10,
      manifest_type:  :gemfile,
      package_manager: :rubygems,
      filename:       "Gemfile",
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
        }
      ]
    )

    spdx = generator.generate(repository_id: 10, repository_name: test_repository_name, namespace_base: test_namespace_base)

    expect(spdx[:creationInfo]).not_to have_key(:comment)
  end

  it "includes PURL for top-level package" do
    spdx = generator.generate(repository_id: 10, repository_name: test_repository_name, namespace_base: test_namespace_base)

    expect(spdx[:packages][0]).to include({
      externalRefs: [{
        referenceCategory: "PACKAGE-MANAGER",
        referenceType: "purl",
        referenceLocator: "pkg:github/mmcfly/power_of_love"
      }]
    })
  end

  it "does not include PURL for top-level package if not github.com" do
    spdx = generator.generate(repository_id: 10, repository_name: test_repository_name, namespace_base: "https://staffship-01.ghe.com")

    expect(spdx[:packages].first).not_to include(:externalRefs)
    expect(spdx[:packages].first).not_to include(:externalRefs)
    expect(spdx[:packages].first).not_to include(:externalRefs)
  end

end

context "denormalized tables" do
  describe DependencyGraph::SBOM::SPDX::Generator do
    before do
      allow(DependencyGraph).to receive(:use_normalized_tables?).and_return(false)
    end

    it_should_behave_like "an sbom generator"
  end
end

context "normalized tables" do
  describe DependencyGraph::SBOM::SPDX::Generator do
    before do
      allow(DependencyGraph).to receive(:use_normalized_tables?).and_return(true)
    end

    it_should_behave_like "an sbom generator"
  end
end
