require "rails_helper"

describe WhereIn do
  it "where_in performs an IN query with multiple columns/values" do
    md = factory.given_manifest_dependency({
        package_name: "rails",
        requirements: "= 5.1.0"
      })

    expect(
      ManifestDependency.where_in(
        [:package_name, :requirements], [["rails", "= 5.1.0"]]))
      .to be_present
  end

  it "where_not_in performs an NOT IN query with multiple columns/values" do
    md = factory.given_manifest_dependency({
      package_name: "rails",
      requirements: "= 5.1.0"
    })

    expect(
      ManifestDependency.where_not_in(
        [:package_name, :requirements], [["rails", "= 5.1.0"]]))
      .to be_empty
  end
end
