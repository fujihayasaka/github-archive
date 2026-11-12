require "spec_helper"
require "active_support"
require "active_support/core_ext"
require_relative "../../../app/manifest_adapters/manifest_adapters/pip/dependency_string"

describe ManifestAdapters::Pip::DependencyString do
  it "normalizes requirements" do
    expect(described_class.parse("pytest")[:requirements]).to eq ""
    expect(described_class.parse("pytest = 3.0.0")[:requirements]).to eq "= 3.0.0"
    expect(described_class.parse("pytest== 3.0.0")[:requirements]).to eq "= 3.0.0"
    expect(described_class.parse("py-test==3.0.0")[:requirements]).to eq "= 3.0.0"
    expect(described_class.parse("py_test==3.0.0")[:requirements]).to eq "= 3.0.0"
    expect(described_class.parse("2pytest==3.0.0")[:requirements]).to eq "= 3.0.0"
    expect(described_class.parse("pytest==3.0.0")[:requirements]).to eq "= 3.0.0"
    expect(described_class.parse("pytest ==3.0.0")[:requirements]).to eq "= 3.0.0"
    expect(described_class.parse("pytest>=3.0.0")[:requirements]).to eq ">= 3.0.0"
    expect(described_class.parse("pytest <= 3.0.0")[:requirements]).to eq "<= 3.0.0"
    expect(described_class.parse("pytest >= 3.0.0, < 4.0.0")[:requirements]).to eq ">= 3.0.0,< 4.0.0"
    expect(described_class.parse("pytest !=3.0.0, < 4.0.0")[:requirements]).to eq "< 3.0.0 || > 3.0.0,< 4.0.0"
    expect(described_class.parse("pytest~=3.0.0")[:requirements]).to eq "~> 3.0.0"
    expect(described_class.parse("pytest==3.0.0 ; python_version < '2.7'")[:requirements]).to eq "= 3.0.0"
    expect(described_class.parse("pytest[extras]")[:requirements]).to eq ""
  end

  it "extracts the package_name" do
    expect(described_class.parse("pytest")[:package_name]).to eq "pytest"
    expect(described_class.parse("pytest = 3.0.0")[:package_name]).to eq "pytest"
    expect(described_class.parse("pytest[extras]")[:package_name]).to eq "pytest"
    expect(described_class.parse("pytest==3.0.0 ; python_version < '2.7'")[:package_name]).to eq "pytest"
  end

  it "normalizes the package_name" do
    expect(described_class.normalize_package_name("pytest_foo")).to eq "pytest-foo"
    expect(described_class.normalize_package_name("pytest_......foo")).to eq "pytest-foo"
    expect(described_class.normalize_package_name("pytest_....._-.foo")).to eq "pytest-foo"
    expect(described_class.normalize_package_name("foo_--pytest_....._-.foo")).to eq "foo-pytest-foo"
  end

  it "raises an exception when parsing fails" do
    expect {
      described_class.parse("This is a sentence")
    }.to raise_error(described_class::ParseError)

    expect {
      described_class.parse("pytest == GARBAGE")
    }.to raise_error(described_class::ParseError)
  end

  it "handles version strings that have letters in them" do
    expect(described_class.parse("pytest>=1.1alpha1")[:requirements]).to eq ">= 1.1alpha1"
    expect(described_class.parse("pytest>=1.0+ubuntu.1")[:requirements]).to eq ">= 1.0+ubuntu.1"
    expect(described_class.parse("pytest>=1.0.post456.dev34")[:requirements]).to eq ">= 1.0.post456.dev34"
    expect(described_class.parse("pytest>=2012.1")[:requirements]).to eq ">= 2012.1"
  end
end
