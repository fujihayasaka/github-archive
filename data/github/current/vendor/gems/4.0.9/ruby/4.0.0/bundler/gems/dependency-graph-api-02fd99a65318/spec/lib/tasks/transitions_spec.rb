require "rails_helper"

Rails.application.load_tasks

describe "normalizing manifest paths" do
  it "deletes duplicative manifests and fixes paths" do
    oldest = create_manifest({
      path: "",
      last_pushed_at: 3.days.ago,
    })
    oldest_dependency = create_dependency(oldest)

    older = create_manifest({
      path: nil,
      last_pushed_at: 2.days.ago,
    })
    older_dependency = create_dependency(older)

    newer = create_manifest({
      path: "/",
      last_pushed_at: 1.day.ago,
    })
    newer_dependency = create_dependency(newer)

    ignored_1 = create_manifest({
      path: "lib",
      last_pushed_at: 1.day.ago,
    })
    ignored_dependency_1 = create_dependency(ignored_1)

    ignored_2 = create_manifest({
      path: "/",
      repository_id: 2,
      last_pushed_at: 1.day.ago,
    })
    ignored_dependency_2 = create_dependency(ignored_2)

    ignored_3 = create_manifest({
      path: nil,
      repository_id: 3,
      last_pushed_at: 1.day.ago,
    })
    ignored_dependency_3 = create_dependency(ignored_3)

    Rake::Task["transitions:normalize_manifest_paths"].invoke

    expect(Manifest.all).to match_array [
      newer,
      ignored_1,
      ignored_2,
      ignored_3
    ]
    expect(newer.reload.path).to eq ""
    expect(ignored_1.reload.path).to eq "lib"
    expect(ignored_2.reload.path).to eq ""
    expect(ignored_3.reload.path).to eq ""

    expect(ManifestDependency.all).to match_array([
      newer_dependency,
      ignored_dependency_1,
      ignored_dependency_2,
      ignored_dependency_3
    ])
  end

  def create_manifest(attrs)
    Manifest.create!({
      repository_id: 1,
      manifest_type: :gemfile,
      package_manager: :rubygems,
      latest_git_ref: "abc123",
    }.merge(attrs))
  end

  def create_dependency(manifest)
    manifest.dependencies.create!({
      package_name: "rails",
      requirements: "",
      last_seen_at_revision: 1,
    })
  end
end
