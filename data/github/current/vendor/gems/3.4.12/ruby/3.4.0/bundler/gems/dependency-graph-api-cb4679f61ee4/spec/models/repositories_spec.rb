require "rails_helper"

describe Repository do
  it "has manifests" do
    repo = Repository.create!({
      github_repository_id: 10
    })

    manifest = repo.manifests.create!({
      package_manager: :rubygems,
      manifest_type:   :gemfile,
      path:            "Gemfile",
      latest_git_ref:  "77dab21",
      last_pushed_at:  Time.now,
    })

    expect(repo.reload.manifests).to eq [manifest]
  end
end
