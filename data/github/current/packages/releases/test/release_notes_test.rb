# typed: true
# frozen_string_literal: true

require "test_helper"

class ReleaseNotesTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @user = create(:user)
    # Repo with v1.0 v2.0 v3.0 etc for creating versioned releases
    @version_tags_repo = create :repository, owner: @user, from_example: :tags_galore
    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  # helper to create a fully merged PR in the repo
  def create_merged_pr(repo, pr_factory_options = {})
    pr = create(:pull_request, :with_mergeable_head,
      repository: repo,
      base_ref: repo.refs.find(repo.default_branch),
      **pr_factory_options
    )
    pr.merge
    # reload to update the branch head
    repo.reload

    pr
  end

  # Some of the default test cases have been moved to the Public interface tests to get coverage there as well

  test "Default notes generation - includes PRs for first release" do
    # set up 2 merged prs
    pr_1 = create(:pull_request, :with_mergeable_head, :merged, repository: @version_tags_repo)
    merge = create(:commit, repository: @version_tags_repo)
    pr_1.update(merge_commit_sha: merge.oid)

    pr_2 = create(:pull_request, :with_mergeable_head, :merged, repository: @version_tags_repo)
    merge = create(:commit, repository: @version_tags_repo)
    pr_2.update(merge_commit_sha: merge.oid)

    # create a new release
    rel = Release.new tag_name: "v1.1", author: @user, repository: @version_tags_repo, target_commitish: "master"
    title, body, warning_message = rel.generate_release_notes
    expected_pr_list = <<~EOS.chomp
        ## What's Changed
        * #{pr_1.title} by @#{pr_1.user.name} in #{pr_1.permalink}
        * #{pr_2.title} by @#{pr_2.user.name} in #{pr_2.permalink}
    EOS

    assert_equal true, body.starts_with?(expected_pr_list)
    assert_equal "", warning_message
  end

  test "Default notes generation - includes PRs since previous semver tag" do
    # first pr for previous tag
    pr_1 = create(:pull_request, :with_mergeable_head, :merged, repository: @version_tags_repo)
    merge = create(:commit, repository: @version_tags_repo)
    pr_1.update(merge_commit_sha: merge.oid)

    # Make a new tag to reference the new merge commit
    tag = @version_tags_repo.tags.build("v4.1.0").create(merge.oid, @user)

    # second pr is for new release
    pr_2 = create(:pull_request, :with_mergeable_head, :merged, repository: @version_tags_repo)
    merge = create(:commit, repository: @version_tags_repo)
    pr_2.update(merge_commit_sha: merge.oid)

    # create new release
    rel = Release.new tag_name: "v4.2.0", author: @user, repository: @version_tags_repo, target_commitish: "master"
    title, body, warning_message = rel.generate_release_notes
    expected_pr_list = <<~EOS.chomp
        ## What's Changed
        * #{pr_2.title} by @#{pr_2.user.name} in #{pr_2.permalink}
    EOS

    assert_equal true, body.include?(expected_pr_list)
    assert_equal "", warning_message
  end

  test "Default notes generation - includes PRs since custom previous tag" do
    # first pr for first tag
    pr_1 = create(:pull_request, :with_mergeable_head, :merged, repository: @version_tags_repo)
    merge = create(:commit, repository: @version_tags_repo)
    pr_1.update(merge_commit_sha: merge.oid)

    # Make a new tag to reference the new merge commit
    tag_1 = @version_tags_repo.tags.build("v4.1.0").create(merge.oid, @user)

    # second pr for second tag
    pr_2 = create(:pull_request, :with_mergeable_head, :merged, repository: @version_tags_repo)
    merge = create(:commit, repository: @version_tags_repo)
    pr_2.update(merge_commit_sha: merge.oid)

    # Make a new tag to reference the new merge commit
    tag_2 = @version_tags_repo.tags.build("v4.2.0").create(merge.oid, @user)

    # third pr for release
    pr_3 = create(:pull_request, :with_mergeable_head, :merged, repository: @version_tags_repo)
    merge = create(:commit, repository: @version_tags_repo)
    pr_3.update(merge_commit_sha: merge.oid)

    # create new release
    rel = Release.new tag_name: "v4.3.0", author: @user, repository: @version_tags_repo, target_commitish: "master"
    title, body, warning_message = rel.generate_release_notes(previous_tag_name: "v4.1.0")
    expected_pr_list = <<~EOS.chomp
        ## What's Changed
        * #{pr_2.title} by @#{pr_2.user.name} in #{pr_2.permalink}
        * #{pr_3.title} by @#{pr_3.user.name} in #{pr_3.permalink}
    EOS

    assert_equal true, body.include?(expected_pr_list)
    assert_equal "", warning_message
  end

  test "Default notes generation - includes PRs since previous release when no prior semver tag" do
    pr_1 = create(:pull_request, :with_mergeable_head, :merged, repository: @version_tags_repo)
    # force this pr to be associated with the first tag
    pr_1.update(merge_commit_sha: @version_tags_repo.ref_to_sha("v1.0"))

    create :release, name: "Version 1.0!", tag_name: "v1.0", author: @user, repository: @version_tags_repo

    # second pr is for new release
    pr_2 = create(:pull_request, :with_mergeable_head, :merged, repository: @version_tags_repo)
    pr_2.update(merge_commit_sha: @version_tags_repo.ref_to_sha("v3.0"))

    # create new release
    rel = Release.new tag_name: "v3.0", author: @user, repository: @version_tags_repo
    title, body, warning_message = rel.generate_release_notes

    # make sure the only pr listed is the one since the previous release
    expected_pr_list = <<~EOS.chomp
        ## What's Changed
        * #{pr_2.title} by @#{pr_2.user.name} in #{pr_2.permalink}
    EOS

    assert_equal true, body.include?(expected_pr_list)
    assert_equal "", warning_message
  end

  test "Default notes generation - no PRs" do

    rel = Release.new tag_name: "v1.0", author: @user, repository: @version_tags_repo
    title, body, warning_message = rel.generate_release_notes

    assert !body.include?("## What's Changed")
    assert warning_message.length > 0
  end

  test "Custom notes generation, default config" do
    content_input = "These are the release notes!"
    rel = Release.new repository: @version_tags_repo, tag_name: "v1.1", author: @user
    title, body = rel.generate_release_notes(template: content_input)
    assert_equal content_input, body
  end

  test "Custom notes generation with variables, default config" do
    Timecop.freeze(Time.local(2000, 1, 1, 0, 0, 0)) do
      content_input = "${{date}}\n${{compare}}"
      rel = Release.new repository: @version_tags_repo, tag_name: "v4.1.0", author: @user
      title, body = rel.generate_release_notes(template: content_input)
      assert_equal "2000-01-01\n**Full Changelog**: https://github.com/#{@user}/#{@version_tags_repo}/compare/v3.0.3...v4.1.0", body
    end
  end

  test "Includes first time contributors in first release" do
    first_time_user_1 = create(:user)
    first_time_user_2 = create(:user)
    commit_1 = create(:commit, repository: @version_tags_repo, committer: first_time_user_1)
    commit_2 = create(:commit, repository: @version_tags_repo, committer: first_time_user_2)

    # user 1 has 1 pr
    pr_1 = create(:pull_request, :with_mergeable_head, :merged, repository: @version_tags_repo, user: first_time_user_1)
    merge = create(:commit, repository: @version_tags_repo)
    pr_1.update(merge_commit_sha: merge.oid)

    # user 2 has 2 prs
    pr_2 = create(:pull_request, :with_mergeable_head, :merged, repository: @version_tags_repo, user: first_time_user_2)
    merge = create(:commit, repository: @version_tags_repo)
    pr_2.update(merge_commit_sha: merge.oid)

    pr_3 = create(:pull_request, :with_mergeable_head, :merged, repository: @version_tags_repo, user: first_time_user_2)
    merge = create(:commit, repository: @version_tags_repo)
    pr_3.update(merge_commit_sha: merge.oid)

    # create a new release
    rel = Release.new tag_name: "v1.1", author: @user, repository: @version_tags_repo, target_commitish: "master"
    rn = Release::ReleaseNotes.new(rel)
    new_contributor_prs = rn.send(:new_contributor_prs)
    expected_new_contributor_prs = [pr_1, pr_2]

    assert_same_elements expected_new_contributor_prs, new_contributor_prs
  end

  test "Includes first time contributors in release with previous semver tag" do
    previous_user = create(:user)

    # previous user has a pr prior to previous semver tag
    pr_1 = create(:pull_request, :with_mergeable_head, :merged, repository: @version_tags_repo, user: previous_user)
    merge = create(:commit, repository: @version_tags_repo)
    pr_1.update(merge_commit_sha: merge.oid)

    tag = @version_tags_repo.tags.build("v4.1.0").create(merge.oid, @user)

    first_time_user = create(:user)

    # both users have prs in the new release
    pr_2 = create(:pull_request, :with_mergeable_head, :merged, repository: @version_tags_repo, user: previous_user)
    merge = create(:commit, repository: @version_tags_repo)
    pr_2.update(merge_commit_sha: merge.oid)

    pr_3 = create(:pull_request, :with_mergeable_head, :merged, repository: @version_tags_repo, user: first_time_user)
    merge = create(:commit, repository: @version_tags_repo)
    pr_3.update(merge_commit_sha: merge.oid)

    rel = Release.new tag_name: "v100.2", author: @user, repository: @version_tags_repo, target_commitish: "master"
    rn = Release::ReleaseNotes.new(rel)

    new_contributor_prs = rn.send(:new_contributor_prs)
    expected_new_contributor_prs = [pr_3]

    assert_same_elements expected_new_contributor_prs, new_contributor_prs
  end

  test "Skips PR in bad state" do
    pr_1 = create(:pull_request, :with_mergeable_head, repository: @version_tags_repo, user: @user)
    commit = create(:commit, repository: @version_tags_repo)
    # This PR is in a bad state, it has a merge_commit_sha but no merged_at
    pr_1.update(merge_commit_sha: commit.oid, merged_at: nil)

    pr_2 = create(:pull_request, :with_mergeable_head, :merged, repository: @version_tags_repo, user: @user)
    commit = create(:commit, repository: @version_tags_repo)
    pr_2.update(merge_commit_sha: commit.oid)

    rel = Release.new tag_name: "v100", author: @user, repository: @version_tags_repo, target_commitish: "master"
    rn = Release::ReleaseNotes.new(rel)
    assert_equal [pr_2], rn.send(:new_contributor_prs)
  end

  test "Handles deleted PR author appropriately" do
    first_time_user = create(:user)
    pr = create_merged_pr(@version_tags_repo, user: first_time_user)
    first_time_user.destroy

    # create a new release
    rel = Release.new tag_name: "v1.1", author: @user, repository: @version_tags_repo, target_commitish: "master"
    title, body = rel.generate_release_notes

    expected_changelog = <<~EOS.chomp
      ## What's Changed
      * #{pr.title} in #{pr.permalink}
    EOS

    # should not be included in new contributor section
    refute body.include?("New Contributors")

    # should render the no author text in the changelog
    assert_includes body, expected_changelog
  end

  context "Custom config" do
    test "respects changelog > categories config, ignores other fields" do
      release_note_config = {
        "title" => "Ignore this since we can't override title yet",
        "changelog" => {
          "default_text" => "This won't work since categories is the only overrideable field",
          "categories" => [{ "title" => "All changes", "labels" => ["*"] }]
        },
        "new_contributors" => {
          "header" => "Please ignore this",
          "default_text" => "and also this!"
        },
        "compare" => {
          "default_text" => "Definitely ignore this as well"
        },
      }

      create(:commit, repository: @version_tags_repo, changes: -> (files) {
        files.add(".github/release.yml", release_note_config.to_yaml)
      })

      pr = create(:pull_request, :with_mergeable_head, :merged, repository: @version_tags_repo)
      merge = create(:commit, repository: @version_tags_repo)
      pr.update(merge_commit_sha: merge.oid)

      rel = Release.new tag_name: "v3.1", author: @user, repository: @version_tags_repo, target_commitish: "master"
      title, body = rel.generate_release_notes

      expected_title = "v3.1"
      expected_changelog = <<~EOS.chomp
        ### All changes
        * #{pr.title} by @#{pr.user} in #{pr.permalink}

      EOS
      expected_new_contribuors = <<~EOS.chomp
        ## New Contributors
        * @#{pr.user} made their first contribution in #{pr.permalink}

      EOS
      expected_compare_text = "**Full Changelog**"

      assert_equal title, expected_title
      assert_includes body, expected_changelog
      assert_includes body, expected_new_contribuors
      assert_includes body, expected_compare_text
    end

    test "PRs placed in specified buckets" do
      # These labels will drive the PR bucketing
      label_1 = create(:label, repository: @version_tags_repo, name: "label1")
      label_2 = create(:label, repository: @version_tags_repo, name: "label2")
      label_3 = create(:label, repository: @version_tags_repo, name: "label3")
      # this label will not be linked to any category
      label_other = create(:label, repository: @version_tags_repo, name: "other")

      release_note_config = {
        "changelog" => {
          "categories" => [
            { "title" => "First section", "labels" => [label_1.name] },
            { "title" => "Multi section", "labels" => [label_2.name, label_3.name] },
            { "title" => "Empty section", "labels" => ["no prs have this label"] },
            { "title" => "Other changes", "labels" => ["*"] },
            { "title" => "Always empty section after *", "labels" => [label_1.name, label_2.name, label_3.name] },
          ]
        },
      }

      create(:commit, repository: @version_tags_repo, changes: -> (files) {
        files.add(".github/release.yml", release_note_config.to_yaml)
      })

      # PRs for the first bucket
      ## PR with matching label
      first_section_pr_1 = create_merged_pr(@version_tags_repo, labels: [label_1])

      ## PR with matching label, and a label matching a later section
      ## this PR should ONLY go in the first section.
      first_section_pr_2 = create_merged_pr(@version_tags_repo, labels: [label_1, label_2])

      # PRs for the second bucket
      ## PR with one matching label
      multi_section_pr_1 = create_merged_pr(@version_tags_repo, labels: [label_2, label_other])

      ## PR with both labels matching
      multi_section_pr_2 = create_merged_pr(@version_tags_repo, labels: [label_2, label_other])

      # PRs for the * bucket
      ## PR with a label not looked for in any category
      other_pr_1 = create_merged_pr(@version_tags_repo, labels: [label_other])

      ## PR with no labels
      other_pr_2 = create_merged_pr(@version_tags_repo)

      # Generate some release notes
      rel = Release.new tag_name: "v3.1", author: @user, repository: @version_tags_repo, target_commitish: "master"
      title, body = rel.generate_release_notes

      expected_changelog = <<~EOS.chomp
        ### First section
        * #{first_section_pr_1.title} by @#{first_section_pr_1.user} in #{first_section_pr_1.permalink}
        * #{first_section_pr_2.title} by @#{first_section_pr_2.user} in #{first_section_pr_2.permalink}
        ### Multi section
        * #{multi_section_pr_1.title} by @#{multi_section_pr_1.user} in #{multi_section_pr_1.permalink}
        * #{multi_section_pr_2.title} by @#{multi_section_pr_2.user} in #{multi_section_pr_2.permalink}
        ### Other changes
        * #{other_pr_1.title} by @#{other_pr_1.user} in #{other_pr_1.permalink}
        * #{other_pr_2.title} by @#{other_pr_2.user} in #{other_pr_2.permalink}
      EOS

      assert_includes body, expected_changelog
    end

    test "omitted title or labels handled" do
      label_1 = create(:label, repository: @version_tags_repo, name: "label1")
      label_2 = create(:label, repository: @version_tags_repo, name: "label2")

      release_note_config = {
        "changelog" => {
          "categories" => [
            { "labels" => [label_1.name, label_2.name] },
            { "title" => "No label section" },
          ]
        },
      }

      create(:commit, repository: @version_tags_repo, changes: -> (files) {
        files.add(".github/release.yml", release_note_config.to_yaml)
      })

      pr_1 = create_merged_pr(@version_tags_repo, labels: [label_1])
      pr_2 = create_merged_pr(@version_tags_repo)

      # Generate some release notes
      rel = Release.new tag_name: "v3.1", author: @user, repository: @version_tags_repo, target_commitish: "master"
      title, body = rel.generate_release_notes

      expected_changelog = <<~EOS.chomp
        ### Pull Requests with labels: #{label_1.name}, #{label_2.name}
        * #{pr_1.title} by @#{pr_1.user} in #{pr_1.permalink}
      EOS

      assert_includes body, expected_changelog
      # section with no labels won't be included
      assert body.exclude?("No label section")
    end

    test "exclude supported at changelog root" do
      label_to_exclude_1 = create(:label, repository: @version_tags_repo, name: "label-exclude")
      label_to_exclude_2 = create(:label, repository: @version_tags_repo, name: "label-exclude-2")
      author_to_exclude_1 = create(:user)
      author_to_exclude_2 = create(:user)

      release_note_config = {
        "changelog" => {
          "exclude" => {
            "labels" => [label_to_exclude_1.name, label_to_exclude_2.name],
            "authors" => [author_to_exclude_1.name, author_to_exclude_2.name]
          },
          "categories" => [
            { "title" => "Cool new stuff", "labels" => ["*"] },
          ]
        },
      }

      create(:commit, repository: @version_tags_repo, changes: -> (files) {
        files.add(".github/release.yml", release_note_config.to_yaml)
      })

      excluded_pr_1 = create_merged_pr(@version_tags_repo, labels: [label_to_exclude_1])
      excluded_pr_2 = create_merged_pr(@version_tags_repo, labels: [label_to_exclude_2])
      excluded_pr_3 = create_merged_pr(@version_tags_repo, user: author_to_exclude_1)
      excluded_pr_4 = create_merged_pr(@version_tags_repo, user: author_to_exclude_2)

      included_pr_1 = create_merged_pr(@version_tags_repo)
      included_pr_2 = create_merged_pr(@version_tags_repo)

      # Generate some release notes
      rel = Release.new tag_name: "v3.1", author: @user, repository: @version_tags_repo, target_commitish: "master"
      title, body = rel.generate_release_notes

      # expected changelog content, include header of next section
      # to ensure changelog section ends with only the expected prs
      expected_changelog = <<~EOS.chomp
        ### Cool new stuff
        * #{included_pr_1.title} by @#{included_pr_1.user} in #{included_pr_1.permalink}
        * #{included_pr_2.title} by @#{included_pr_2.user} in #{included_pr_2.permalink}

        ## New Contributors
      EOS

      assert_includes body, expected_changelog
    end

    test "exclude supported in categories" do
      label_1 = create(:label, repository: @version_tags_repo, name: "label-1")
      label_2 = create(:label, repository: @version_tags_repo, name: "label-2")
      author_to_exclude = create(:user)

      release_note_config = {
        "changelog" => {
          "categories" => [
            { "title" => "Cool new stuff",
              "labels" => [label_1.name],
              "exclude" => {
                "labels" => [label_2.name],
              },
            },
            { "title" => "Some other stuff",
              "labels" => [label_2.name],
              "exclude" => {
                "authors" => [author_to_exclude.name],
              },
            },
            { "title" => "Everything else",
              "labels" => ["*"],
            },
          ]
        },
      }

      create(:commit, repository: @version_tags_repo, changes: -> (files) {
        files.add(".github/release.yml", release_note_config.to_yaml)
      })

      # this pr will be included in the first category since the label matches
      pr_1 = create_merged_pr(@version_tags_repo, labels: [label_1])

      # this pr would be included in the first category since one of its labels matches,
      # BUT since its other label is excluded from the first category, it won't be included.
      # It will then be included in the second category since its other label matches the second category
      pr_2 = create_merged_pr(@version_tags_repo, labels: [label_1, label_2])

      # this pr will be included in the second category since the label matches
      pr_3 = create_merged_pr(@version_tags_repo, labels: [label_2])

      # this pr would be included in the second category since one of its labels matches,
      # BUT since its author is excluded from the second category, it won't be included.
      # It will then be included in the final "*" category
      pr_4 = create_merged_pr(@version_tags_repo, labels: [label_2], user: author_to_exclude)

      # Generate some release notes
      rel = Release.new tag_name: "v3.1", author: @user, repository: @version_tags_repo, target_commitish: "master"
      title, body = rel.generate_release_notes

      # expected changelog content, include header of next section
      # to ensure changelog section ends with only the expected prs
      expected_changelog = <<~EOS.chomp
        ### Cool new stuff
        * #{pr_1.title} by @#{pr_1.user} in #{pr_1.permalink}
        ### Some other stuff
        * #{pr_2.title} by @#{pr_2.user} in #{pr_2.permalink}
        * #{pr_3.title} by @#{pr_3.user} in #{pr_3.permalink}
        ### Everything else
        * #{pr_4.title} by @#{pr_4.user} in #{pr_4.permalink}

        ## New Contributors
      EOS

      assert_includes body, expected_changelog
    end

    test "throws error for invalid yaml" do
      # the unquoted * in here is invalid yaml syntax
      invalid_yaml = "changelog: *"

      create(:commit, repository: @version_tags_repo, changes: -> (files) {
        files.add(".github/release.yml", invalid_yaml)
      })

      # Generate some release notes, throwing an error
      rel = Release.new tag_name: "v3.1", author: @user, repository: @version_tags_repo, target_commitish: "master"
      err = assert_raises Releases::Error do
        rel.generate_release_notes
      end

      assert_includes err.message, "Could not parse .github/release.yml"
    end

    test "throws errors for invalid config" do
      wrong_config = {
        "changelog" => {
          "categories" => "foo", # supposed to be an array
          "exclude" => "bar" # supposed to be an object
        }
      }

      nested_very_wrong_config = {
        "changelog" => {
          "categories" => [{
            "labels" => [123], # supposed to be a string array
            "exclude" => {
              "authors" => "bar", # supposed to be an array
              "labels" => [{ "test" => true }] # supposed to be a string array
            },
            "title" => { "title" => "error" }, # supposed to be a string
          }],
          "exclude" => {
            "authors" => "bar", # supposed to be an array
            "labels" => [{ "test" => true }] # supposed to be a string array
          }
        }
      }

      wrong_config_commit = create(:commit, repository: @version_tags_repo, changes: -> (files) {
        files.add(".github/release.yml", wrong_config.to_yaml)
      })

      nested_very_wrong_config_commit = create(:commit, repository: @version_tags_repo, changes: -> (files) {
        files.add(".github/release.yml", nested_very_wrong_config.to_yaml)
      })

      # Generate some release notes, throwing an error
      rel = Release.new tag_name: "v3.1", author: @user, repository: @version_tags_repo, target_commitish: wrong_config_commit.oid
      err = assert_raises Releases::ConfigurationError do
        rel.generate_release_notes
      end

      assert_includes err.errors, "The property '#/changelog/categories' of type string did not match the following type: array"
      assert_includes err.errors, "The property '#/changelog/exclude' of type string did not match the following type: object"

      # Generate some more notes, with a bigger error
      rel2 = Release.new tag_name: "v3.1", author: @user, repository: @version_tags_repo, target_commitish: nested_very_wrong_config_commit.oid
      err = assert_raises Releases::Error do
        rel2.generate_release_notes
      end

      assert_includes err.errors, "The property '#/changelog/categories/0/labels/0' of type integer did not match the following type: string"
      assert_includes err.errors, "The property '#/changelog/categories/0/title' of type object did not match the following type: string"
      assert_includes err.errors, "The property '#/changelog/categories/0/exclude/authors' of type string did not match the following type: array"
      assert_includes err.errors, "The property '#/changelog/categories/0/exclude/labels/0' of type object did not match the following type: string"
      assert_includes err.errors, "The property '#/changelog/exclude/authors' of type string did not match the following type: array"
      assert_includes err.errors, "The property '#/changelog/exclude/labels/0' of type object did not match the following type: string"

    end

    test "allows various empty/ignored config without errors" do
      empty = create(:commit, repository: @version_tags_repo, changes: -> (files) {
        files.add(".github/release.yml", "")
      })

      empty_object = create(:commit, repository: @version_tags_repo, changes: -> (files) {
        files.add(".github/release.yml", {}.to_yaml)
      })

      ignored_content = create(:commit, repository: @version_tags_repo, changes: -> (files) {
        files.add(".github/release.yml", { "other" => "foo" }.to_yaml)
      })

      # Generate some release notes
      rel = Release.new tag_name: "v3.1", author: @user, repository: @version_tags_repo, target_commitish: empty.oid
      rel2 = Release.new tag_name: "v3.1", author: @user, repository: @version_tags_repo, target_commitish: empty_object.oid
      rel3 = Release.new tag_name: "v3.1", author: @user, repository: @version_tags_repo, target_commitish: ignored_content.oid
      title1, body1 = rel.generate_release_notes
      title2, body2 = rel2.generate_release_notes
      title3, body3 = rel3.generate_release_notes

      assert [body1, body2, body3].all?(&:present?)
    end

    test "allows .yml and .yaml files, adds comment clarifying config source" do
      release_note_config = {
        "changelog" => {
          "categories" => [
            { "labels" => ["*"] },
            { "title" => "All changes" },
          ]
        },
      }

      # First try yaml
      create(:commit, repository: @version_tags_repo, changes: -> (files) {
        files.add(".github/release.yaml", release_note_config.to_yaml)
      })

      rel = Release.new tag_name: "v3.1", author: @user, repository: @version_tags_repo, target_commitish: "master"
      title, body = rel.generate_release_notes

      assert_includes body, "<!-- Release notes generated using configuration in .github/release.yaml at master -->"

      # Now lets do yml
      yml_commit = create(:commit, repository: @version_tags_repo, changes: -> (files) {
        files.add(".github/release.yml", release_note_config.to_yaml)
      })

      rel = Release.new tag_name: "v3.1", author: @user, repository: @version_tags_repo, target_commitish: yml_commit.abbreviated_oid
      title, body = rel.generate_release_notes

      assert_includes body, "<!-- Release notes generated using configuration in .github/release.yml at #{yml_commit.abbreviated_oid} -->"
    end
  end

  test "logs a hydro event when notes are generated" do
    release = Release.new repository: @version_tags_repo, tag_name: "v1.1", author: @user
    title, body = release.generate_release_notes

    refute_empty title, body
    message = {
      request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
      release: Hydro::EntitySerializer.release(release),
      repository: Hydro::EntitySerializer.repository(release.repository),
      repository_owner: Hydro::EntitySerializer.user(T.must(release.repository).owner),
    }
    assert_hydro_published_partial(message, schema: "github.releases.v1.ReleaseNotesGenerated")
  end
end
