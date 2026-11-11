require "rails_helper"

describe ManifestAdapters::Actions::Adapter do
  it "recognizes workflow.yaml files" do
    expect(described_class.test(filename: "workflow.yaml", path: ".github/workflows/")).to be_truthy
    expect(described_class.test(filename: "workflow.yml", path: ".github/workflows/")).to be_truthy
    expect(described_class.test(filename: "doing_actions.yaml", path: ".github/workflows/")).to be_truthy
    expect(described_class.test(filename: "doing-actions.yaml", path: ".github/workflows/")).to be_truthy
    expect(described_class.test(filename: "check-dependabot.yaml", path: ".github/workflows/")).to be_truthy
    expect(described_class.test(filename: "doing---actions.yaml", path: ".github/workflows/")).to be_truthy
    expect(described_class.test(filename: "doing---actions-.yaml", path: ".github/workflows/")).to be_truthy
    expect(described_class.test(filename: "-doing---actions.yaml", path: ".github/workflows/")).to be_truthy

    expect(described_class.test(filename: "workflow.yaml", path: nil)).to be_falsey
    expect(described_class.test(filename: "workflow.yaml", path: ".github/")).to be_falsey
    expect(described_class.test(filename: "workflow.yaml", path: ".github/workflowno/")).to be_falsey
    expect(described_class.test(filename: "workflow.yaml", path: "github/workflows/")).to be_falsey
    expect(described_class.test(filename: "workflow.yaml", path: "/")).to be_falsey
    expect(described_class.test(filename: "not-workflow.yaml", path: nil)).to be_falsey
    expect(described_class.test(filename: "workflow.yaml.stuff", path: nil)).to be_falsey
    expect(described_class.test(filename: "workflow.yml", path: "j.github/workflows/")).to be_falsey
    expect(described_class.test(filename: "workflow.yml", path: "jgithub/workflows/")).to be_falsey
    expect(described_class.test(filename: "/.yaml", path: ".github/workflows/")).to be_falsey
    expect(described_class.test(filename: "work_is_flowing.yaml", path: ".github/workflows/another_sub_folder/")).to be_falsey
    expect(described_class.test(filename: "check-dependabot.yaml", path: ".github/workflows/another-sub-folder")).to be_falsey
    expect(described_class.test(filename: "doing---actions.yaml", path: ".github/workflows/sub-folder")).to be_falsey
    expect(described_class.test(filename: "weird--foldernames.yml", path: ".github/workflows/workflow.yaml")).to be_falsey
  end
end
