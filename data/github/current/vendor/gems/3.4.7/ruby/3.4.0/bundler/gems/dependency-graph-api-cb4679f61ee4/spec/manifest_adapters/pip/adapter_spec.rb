require "rails_helper"

describe ManifestAdapters::Pip::Adapter do
  it "recognizes Pipfiles" do
    expect(described_class.test(filename: "Pipfile", path: nil)).to be_truthy
    expect(described_class.test(filename: "Pipfile", path: "")).to be_truthy
    expect(described_class.test(filename: "Pipfile", path: "/")).to be_truthy
    expect(described_class.test(filename: "Pipfile", path: "config")).to be_truthy
    expect(described_class.test(filename: "Pipfile.lock", path: nil)).to be_truthy
    expect(described_class.test(filename: "Pipfile.lock", path: "")).to be_truthy
    expect(described_class.test(filename: "Pipfile.lock", path: "/")).to be_truthy

    expect(described_class.test(filename: "not-Pipfile", path: nil)).to be_falsey
    expect(described_class.test(filename: "not-Pipfile.lock", path: nil)).to be_falsey
  end

  it "recognizes setup.py files" do
    expect(described_class.test(filename: "setup.py", path: nil)).to be_truthy
    expect(described_class.test(filename: "setup.py", path: "")).to be_truthy
    expect(described_class.test(filename: "setup.py", path: "/")).to be_truthy
    expect(described_class.test(filename: "setup.py", path: "config")).to be_truthy

    expect(described_class.test(filename: "setup.py.bak", path: nil)).to be_falsey
  end

  it "recognizes pyproject.toml files" do
    expect(described_class.test(filename: "pyproject.toml", path: nil)).to be_truthy
    expect(described_class.test(filename: "pyproject.toml", path: "")).to be_truthy
    expect(described_class.test(filename: "pyproject.toml", path: "/")).to be_truthy
    expect(described_class.test(filename: "pyproject.toml", path: "config")).to be_truthy

    expect(described_class.test(filename: "pyproject.toml.bak", path: nil)).to be_falsey
  end

  it "recognizes requirements.txt manifests" do
    expect(described_class.test(filename: "requirements.txt", path: nil)).to be_truthy
    expect(described_class.test(filename: "requirements.txt", path: "")).to be_truthy
    expect(described_class.test(filename: "requirements.txt", path: "/")).to be_truthy
    expect(described_class.test(filename: "development.txt", path: "requirements")).to be_truthy

    expect(described_class.test(filename: "readme.txt", path: nil)).to be_falsey
  end

  it "recognizes custom named require(ments).txt manifests" do
    expect(described_class.test(filename: "dev-requirements.txt", path: nil)).to be_truthy
    expect(described_class.test(filename: "pip_requirements.txt", path: "")).to be_truthy
    expect(described_class.test(filename: "requirements-pg.txt", path: "/")).to be_truthy
    expect(described_class.test(filename: "requirements_test.txt", path: "requirements")).to be_truthy
    expect(described_class.test(filename: "pypi-requirements.txt", path: "config/requirements")).to be_truthy

    expect(described_class.test(filename: "require.txt", path: "/")).to be_truthy
    expect(described_class.test(filename: "require-test.txt", path: "")).to be_truthy
    expect(described_class.test(filename: "require_test.txt", path: nil)).to be_truthy

    expect(described_class.test(filename: "access_required.txt", path: nil)).to be_falsey
    expect(described_class.test(filename: "requireJs.txt", path: "")).to be_falsey
    expect(described_class.test(filename: "require_global.html.txt", path: nil)).to be_falsey
    expect(described_class.test(filename: "require-2017.11.15.txt", path: nil)).to be_falsey
    expect(described_class.test(filename: "require 20 19 .txt", path: nil)).to be_falsey
  end

  it "recognizes poetry.lock files" do
    expect(described_class.test(filename: "poetry.lock", path: nil)).to be_truthy
    expect(described_class.test(filename: "poetry.lock", path: "")).to be_truthy
    expect(described_class.test(filename: "poetry.lock", path: "/")).to be_truthy
    expect(described_class.test(filename: "poetry.lock", path: "config")).to be_truthy

    expect(described_class.test(filename: "poetry.lock.bak", path: nil)).to be_falsey
    expect(described_class.test(filename: "little_poetry.lock", path: nil)).to be_falsey
  end
end
