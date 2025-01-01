require "rails_helper"

describe "reassigning packages" do
  before do
    factory do
      given_package("httparty", "0.14.0")
        .update_package(repository_id: 200)
        .update_package_repository(github_repository_id: 200)

      Repository.create(github_repository_id: 1000)
    end
  end

  it "reassigns the package repository ID" do
    package = get_package("httparty")

    expect(package.repository_id).to eq(200)

    mutation = <<-QUERY.strip_heredoc
      mutation ReassignPackage($input: ReassignPackageInput!) {
        reassignPackage(input: $input) {
          clientMutationId
        }
      }
    QUERY

    query(mutation, {
      input: {
        packageManager: "RUBYGEMS",
        packageName: "httparty",
        repositoryId: 1000,
      }
    })

    expect(package.reload.repository_id).to eq(1000)
  end

  it "returns the clientMutationId" do
    mutation = <<-QUERY.strip_heredoc
      mutation ReassignPackage($input: ReassignPackageInput!) {
        reassignPackage(input: $input) {
          clientMutationId
        }
      }
    QUERY

    query(mutation, {
      input: {
        packageManager: "RUBYGEMS",
        packageName: "httparty",
        repositoryId: 1000,
        clientMutationId: "1234five",
      }
    })

    expect(results).to eq({
      reassignPackage: {
        clientMutationId: "1234five"
      }
    })
  end
end
