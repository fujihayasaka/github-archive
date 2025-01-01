# typed: true
# frozen_string_literal: true

require "test_helper"

class CreatingAttachmentTest < GitHub::TestCase
  include UploadableTestHelpers
  include DogstatsTestHelpers

  fixtures do
    GitHub.user_images_cdn_url = "https://user-images-cdn.githubusercontent.com/"
    @owner = create(:user)
    @uploader = create(:user)
    @author = create(:verified_user)
    @repo = create :repository, owner: @author, has_discussions: true, from_example: :review_comment_source
    @private_repo = create(:private_repository, owner: @author, has_discussions: true, from_example: :pull_request_source)
    @fork = create(:fork_repository, forker: @owner, fork_repo: @repo, from_example: :review_comment_fork)

    @issue = create(:issue, user: @author, repository: @repo)
    @private_issue = create(:issue, user: @author, repository: @private_repo)
    @pull =
      create(:pull_request,
        repository: @repo,
        base_repository: @repo,
        base_user: @repo.owner,
        base_ref: "master",
        head_repository: @fork,
        head_user: @fork.owner,
        head_ref: "topic",
        issue: @issue,
        user: @owner,
      )

    # Setup for creating valid PR review in test
    review_repo = repo = create(:private_repository, owner: @author, from_example: :pull_request_source)
    fork = create(:fork_repository, forker: @author, fork_repo: review_repo, from_example: :pull_request_fork)

    issue = create(:issue, {
      user: @author,
      repository: review_repo,
      number: 7,
    })

    @review_pr = create(:pull_request, {
      issue: issue,
      base_repository: review_repo,
      base_user: review_repo.owner,
      base_ref: "master",
      head_repository: fork,
      head_user: @author,
      head_ref: "topic",
    })

    @issue.pull_request = @pull
    @discussion = create(:discussion, user: @author, repository: @repo)

    @draft_issue = create(:draft_issue)

    @asset = save_file_for_uploadable(UserAsset.new(uploader: @uploader))
    @asset2 = save_file_for_uploadable(UserAsset.new(uploader: @uploader))
    @video_asset = save_file_for_uploadable(UserAsset.new(uploader: @uploader), name: "vid.mp4", content_type: "video/mp4")

    enable_feature_flag(:attach_repository_files)
    @repository_file = save_file_for_uploadable(
      RepositoryFile.new(uploader: @owner, repository: @repo),
      name: "test.pdf",
      content_type: "application/pdf",
    )
    @repository_file2 = save_file_for_uploadable(
      RepositoryFile.new(uploader: @owner, repository: @repo),
      name: "test2.pdf",
      content_type: "application/pdf",
    )
  end

  teardown_once do
    GitHub.s3_uploads_enabled = nil
    GitHub.user_images_cdn_url = nil
  end

  environments = {
    s3: lambda {
      GitHub.s3_uploads_enabled = true
    },
  }

  environments.each do |upload_type, env_settings|
    test "#{upload_type} uploads: tracks the associated entity" do
      asset3 = save_file_for_uploadable(UserAsset.new(uploader: @uploader))
      asset3.id = asset3.id * 2

      env_settings.call
      issue = create_attachment(Issue, [@asset, @asset2, asset3])
      refute_nil issue.entity
      assert_equal 2, issue.reload.attachments.size
      issue.attachments.each_with_index do |att, i|
        assert_includes [@asset, @asset2], att.asset
        assert_equal issue.entity, att.entity, "attachment #{i}"
      end

      assert_dogstats_increment 1, "attach_matching_assets.runs", tags: ["class:issue", "in_background:true"]
    end

    test "#{upload_type} uploads: scans for attachments" do
      env_settings.call
      issue = build_attachment(Issue, @asset)
      assert_equal 1, issue.body_asset_matches.size
      assert match = issue.body_asset_matches.first, issue.body
      assert_equal @asset.guid, match.asset_guid, "#{issue.body}\n#{match.inspect}"

      # skip intermittent test failure for GHE instances with 100M+ users
      if upload_type != :file || @uploader.id.to_s.size < 9
        assert_equal @uploader.id.to_s, match.user_id, "#{issue.body}\n#{match.inspect}"
      end
    end

    test "#{upload_type} uploads: scans for video attachments" do
      env_settings.call
      setup_allowed_hosts

      issue = build_video_attachment(Issue, @video_asset, @private_repo)
      assert_equal 1, issue.body_asset_matches.size
      assert match = issue.body_asset_matches.first, issue.body
      assert_equal @video_asset.guid, match.asset_guid, "#{issue.body}\n#{match.inspect}"
    end

    test "#{upload_type} uploads: scans for file attachments" do
      env_settings.call

      issue = build_file_attachment(Issue, @repository_file, @private_repo)
      assert_equal 1, issue.body_asset_matches.size
      assert match = issue.body_asset_matches.first, issue.body
      assert_equal @repository_file.id, match.asset_id.to_i, "#{issue.body}\n#{match.inspect}"
    end

    test "#{upload_type} uploads: adds image attachments on update" do
      env_settings.call

      # existing issue has no attachments... body is updated to add new asset
      perform_enqueued_jobs(only: [AttachMatchingAssetsJob, IssueOrchestration.job_class]) do
        @issue.update_body(attachment_body_for(@asset), @author)
      end

      assert_asset_attached { @issue }

      assert_equal 1, @asset.attachments.count
      assert_equal 1, @issue.attachments.count
      assert_equal 0, @asset2.attachments.count

      # issue body is updated again to add 2nd asset
      perform_enqueued_jobs(only: [AttachMatchingAssetsJob, IssueOrchestration.job_class]) do
        @issue.update_body(@issue.body += attachment_body_for(@asset, @asset2), @author)
      end

      assert_equal 1, @asset.attachments.count
      assert_equal 1, @asset2.attachments.count
      assert_equal 2, @issue.attachments.count
    end

    test "#{upload_type} uploads: adds file attachments on update" do
      env_settings.call

      # existing issue has no attachments... body is updated to add new asset
      perform_enqueued_jobs(only: [AttachMatchingAssetsJob, IssueOrchestration.job_class]) do
        @issue.update_body(file_attachment_body_for(@repository_file), @author)
      end

      assert_repository_file_attached { @issue }

      assert_equal 1, @repository_file.attachments.count
      assert_equal 1, @issue.attachments.count
      assert_equal 0, @repository_file2.attachments.count

      # issue body is updated again to add 2nd asset
      perform_enqueued_jobs(only: [AttachMatchingAssetsJob, IssueOrchestration.job_class]) do
        @issue.update_body(@issue.body += file_attachment_body_for(@repository_file, @repository_file2), @author)
      end

      assert_equal 1, @repository_file.attachments.count
      assert_equal 1, @repository_file2.attachments.count
      assert_equal 2, @issue.attachments.count
    end

    test "#{upload_type} uploads: adds both file and image attachments on update" do
      env_settings.call

      # existing issue has no attachments... body is updated to add new asset
      perform_enqueued_jobs(only: [AttachMatchingAssetsJob, IssueOrchestration.job_class]) do
        @issue.update_body(attachment_body_for(@asset) + file_attachment_body_for(@repository_file), @author)
      end

      assert_equal 1, @asset.attachments.count
      assert_equal 2, @issue.attachments.count
      assert_equal 1, @repository_file.attachments.count
    end

    test "#{upload_type} uploads: clears removed assets on update" do
      env_settings.call
      setup_allowed_hosts

      # existing issue has no attachments... body is updated to add new asset
      perform_enqueued_jobs(only: [IssueOrchestration.job_class, AttachMatchingAssetsJob]) do
        @private_issue.update_body(attachment_body_for(@asset), @author)
      end
      assert_asset_attached { @private_issue }

      assert_equal 1, @asset.attachments.count
      assert_equal 1, @private_issue.attachments.count
      assert_equal 0, @asset2.attachments.count

      # issue body is updated again to replace @asset with @asset2
      perform_enqueued_jobs(only: [IssueOrchestration.job_class, AttachMatchingAssetsJob]) do
        @private_issue.update_body(attachment_body_for(@asset2), @author)
      end

      assert_equal 0, @asset.attachments.count
      assert_equal 1, @private_issue.attachments.count
      assert_equal 1, @asset2.attachments.count

      assert_same_elements [@asset2], @private_issue.attachments.reload.map(&:asset)

      # issue body is updated again to replace @asset2 with @video_asset
      perform_enqueued_jobs(only: [IssueOrchestration.job_class, AttachMatchingAssetsJob]) do
        @private_issue.update_body(video_attachment_body_for(@video_asset), @author)
      end

      assert_equal 0, @asset2.attachments.count
      assert_equal 1, @private_issue.attachments.count
      assert_equal 1, @video_asset.attachments.count

      assert_same_elements [@video_asset], @private_issue.attachments.reload.map(&:asset)
    end

    test "#{upload_type} uploads: clears removed repository files on update" do
      env_settings.call
      setup_allowed_hosts

      # existing issue has no attachments... body is updated to add new asset
      perform_enqueued_jobs(only: [IssueOrchestration.job_class, AttachMatchingAssetsJob]) do
        @private_issue.update_body(file_attachment_body_for(@repository_file), @author)
      end
      assert_repository_file_attached { @private_issue }

      assert_equal 1, @repository_file.attachments.count
      assert_equal 1, @private_issue.attachments.count
      assert_equal 0, @repository_file2.attachments.count

      # issue body is updated again to replace @repository_file with @repository_file2
      perform_enqueued_jobs(only: [IssueOrchestration.job_class, AttachMatchingAssetsJob]) do
        @private_issue.update_body(file_attachment_body_for(@repository_file2), @author)
      end

      assert_equal 0, @repository_file.attachments.count
      assert_equal 1, @private_issue.attachments.count
      assert_equal 1, @repository_file2.attachments.count

      assert_same_elements [@repository_file2], @private_issue.attachments.reload.map(&:asset)

      # issue body is updated again to remove @repository_file2
      perform_enqueued_jobs(only: [IssueOrchestration.job_class, AttachMatchingAssetsJob]) do
        @private_issue.update_body("test", @author)
      end

      assert_equal 0, @repository_file2.attachments.count
      assert_equal 0, @private_issue.attachments.count

      assert_same_elements [], @private_issue.attachments.reload.map(&:asset)
    end

    test "#{upload_type} uploads: does not create attachments for repository files in non-repository context" do
      enable_feature_flag(:gist_attachment_scanning)

      env_settings.call

      contents = [
        { name: "file1.md", value: file_attachment_body_for(@repository_file) },
      ]

      gist = create_gist_with_attachments(@owner, contents)

      assert_equal 0, gist.attachments.count
      assert_equal @asset.attachments.reload, gist.attachments.reload
    end

    test "#{upload_type} uploads: does not add file attachments if feature flag is disabled" do
      env_settings.call

      disable_feature_flag(:attach_repository_files)

      # existing issue has no attachments... body is updated to add new asset
      perform_enqueued_jobs(only: [AttachMatchingAssetsJob, IssueOrchestration.job_class]) do
        @issue.update_body(file_attachment_body_for(@repository_file), @author)
      end

      assert_equal 0, @repository_file.attachments.count
      assert_equal 0, @issue.attachments.count
    end


    test "#{upload_type} uploads: creates attachment to Issue" do
      env_settings.call
      assert_asset_attached_to Issue, @asset
    end

    test "#{upload_type} uploads: creates attachment to IssueComment" do
      env_settings.call
      assert_asset_attached_to IssueComment, @asset, repository: nil, issue: @issue
    end

    test "#{upload_type} uploads: creates attachment to Discussion" do
      env_settings.call
      assert_asset_attached_to Discussion, @asset
    end

    test "#{upload_type} uploads: creates attachment to DiscussionComment" do
      env_settings.call
      assert_asset_attached_to DiscussionComment, @asset, repository: nil, discussion: @discussion
    end

    test "#{upload_type} uploads: creates attachment to CommitComment" do
      env_settings.call
      assert_asset_attached_to CommitComment, @asset, commit_id: @pull.base_sha,
        path: "abc.def"
    end

    test "#{upload_type} uploads: #{upload_type} uploads: creates attachment to PullRequestReview" do
      env_settings.call

      assert_asset_attached_to PullRequestReview, @asset, pull_request: @review_pr,
        user: @author,
        head_sha: @review_pr.head_sha,
        formatter: :markdown,
        state: 40
    end

    test "#{upload_type} uploads: #{upload_type} uploads: creates attachment to PullRequestReviewComment" do
      env_settings.call
      assert_asset_attached_to PullRequestReviewComment, @asset, repository: nil,
        pull_request: @pull
    end

    context "#{upload_type} uploads: DraftIssue" do
      test "creates attachments for Draft Issues" do
        enable_feature_flag(:draft_issue_attachment_scanning)

        env_settings.call

        # Save the draft issue with an attachment in the body. Saving will trigger the
        # attachment scanning callback
        perform_enqueued_jobs(only: [AttachMatchingAssetsJob]) do
          @draft_issue.update!(body: attachment_body_for(@asset))
        end

        assert_equal 1, @asset.attachments.count
        assert_equal @asset.attachments.reload, @draft_issue.attachments.reload

        att = @asset.attachments.first
        assert_equal @asset, att.asset
        assert_equal @draft_issue, att.attachable
        assert_equal @draft_issue.creator, att.attacher
        assert_equal @draft_issue.memex_project, att.entity

        # Now save the draft issue with an empty body. This will retrigger the attachment
        # scanning callback, which should remove the no-longer-present attachment
        perform_enqueued_jobs(only: [AttachMatchingAssetsJob]) do
          @draft_issue.update!(body: "")
        end

        assert_equal 0, @asset.attachments.count
        assert_equal 0, @draft_issue.attachments.count
      end

      test "does not create attachments when feature flag is disabled" do
        disable_feature_flag(:draft_issue_attachment_scanning)

        env_settings.call

        # Save the draft issue with an attachment in the body. Saving will trigger the
        # attachment scanning callback
        @draft_issue.update!(body: attachment_body_for(@asset))

        assert_enqueued_jobs 0, only: AttachMatchingAssetsJob
        assert_equal 0, @asset.attachments.count
        assert_equal @asset.attachments.reload, @draft_issue.attachments.reload
      end
    end

    context "#{upload_type} uploads: Gist Comment" do
      test "creates attachments to Gist Comment" do
        enable_feature_flag(:gist_comment_attachment_scanning)

        env_settings.call
        gist = create(:gist)
        assert_asset_attached_to GistComment, @asset, gist: gist, repository: nil
      end

      test "does not create attachments when feature flag disabled" do
        disable_feature_flag(:gist_comment_attachment_scanning)

        env_settings.call
        gist = create(:gist)

        comment = create_attachment(GistComment, @asset, gist: gist, repository: nil)
        assert_equal 0, @asset.attachments.count
        assert_equal @asset.attachments.reload, comment.attachments.reload
      end
    end

    context "#{upload_type} uploads: wikis" do
      test "#{upload_type} uploads: creates attachment to updated Wiki page" do
        enable_feature_flag(:wiki_attachment_scanning)

        env_settings.call

        @repo.initialize_wiki(@repo.owner)
        wiki = @repo.unsullied_wiki

        example_repo :wiki, wiki
        page = wiki.pages.first

        repo_wiki = RepositoryWiki.find_by(repository: @repo)

        perform_enqueued_jobs(only: [AttachMatchingAssetsJob]) do
          page.update(page.name, attachment_body_for(@asset), :markdown, "new commit message", @repo.owner)
        end

        wiki_attachments = Attachment.where(attachable: repo_wiki)
        assert_equal 1, wiki_attachments.count
        assert_equal @asset.attachments.reload, wiki_attachments.reload

        att = @asset.attachments.first
        assert_equal @asset, att.asset
        assert_equal repo_wiki, att.attachable
        assert_equal @repo.owner, att.attacher
        assert_equal @repo, att.entity
      end

      test "#{upload_type} uploads: creates attachment to new Wiki page" do
        enable_feature_flag(:wiki_attachment_scanning)
        env_settings.call

        @repo.initialize_wiki(@repo.owner)
        wiki = @repo.unsullied_wiki
        example_repo :wiki, wiki
        repo_wiki = RepositoryWiki.find_by(repository: @repo)

        perform_enqueued_jobs(only: [AttachMatchingAssetsJob]) do
          wiki.pages.create("new page", :markdown, attachment_body_for(@asset), "new commit message", @repo.owner)
        end

        wiki_attachments = Attachment.where(attachable: repo_wiki)
        assert_equal 1, wiki_attachments.count
        assert_equal @asset.attachments.reload, wiki_attachments.reload

        att = @asset.attachments.first
        assert_equal @asset, att.asset
        assert_equal repo_wiki, att.attachable
        assert_equal @repo.owner, att.attacher
        assert_equal @repo, att.entity
      end

      test "#{upload_type} uploads: does not remove old attachments from Wiki page" do
        enable_feature_flag(:wiki_attachment_scanning)

        env_settings.call

        @repo.initialize_wiki(@repo.owner)
        wiki = @repo.unsullied_wiki

        example_repo :wiki, wiki
        page = wiki.pages.first

        repo_wiki = RepositoryWiki.find_by(repository: @repo)

        perform_enqueued_jobs(only: [AttachMatchingAssetsJob]) do
          page.update(page.name, attachment_body_for(@asset), :markdown, "new commit message", @repo.owner)
        end

        wiki_attachments = Attachment.where(attachable: repo_wiki)
        assert_equal 1, wiki_attachments.count
        assert_equal @asset.attachments.reload, wiki_attachments.reload

        page = wiki.pages.first
        perform_enqueued_jobs(only: [AttachMatchingAssetsJob]) do
          page.update(page.name, "no attachments", :markdown, "new commit message2", @repo.owner)
        end

        assert_equal 1, wiki_attachments.count
        assert_equal @asset.attachments.reload, wiki_attachments.reload
      end

      test "#{upload_type} uploads: uses editing user as attacher" do
        enable_feature_flag(:wiki_attachment_scanning)

        env_settings.call

        @repo.initialize_wiki(@repo.owner)
        wiki = @repo.unsullied_wiki

        example_repo :wiki, wiki
        page = wiki.pages.first

        repo_wiki = RepositoryWiki.find_by(repository: @repo)

        attacher = create(:user)

        perform_enqueued_jobs(only: [AttachMatchingAssetsJob]) do
          page.update(page.name, attachment_body_for(@asset), :markdown, "new commit message", attacher)
        end

        wiki_attachments = Attachment.where(attachable: repo_wiki)
        assert_equal 1, wiki_attachments.count
        assert_equal @asset.attachments.reload, wiki_attachments.reload

        att = @asset.attachments.first
        assert_equal attacher, att.attacher
      end

      test "does not create attachments when feature flag is disabled" do
        disable_feature_flag(:wiki_attachment_scanning)

        env_settings.call

        @repo.initialize_wiki(@repo.owner)
        wiki = @repo.unsullied_wiki

        example_repo :wiki, wiki
        page = wiki.pages.first

        repo_wiki = RepositoryWiki.find_by(repository: @repo)

        page.update(page.name, attachment_body_for(@asset), :markdown, "new commit message", @repo.owner)

        assert_enqueued_jobs 0, only: AttachMatchingAssetsJob
        wiki_attachments = Attachment.where(attachable: repo_wiki)
        assert_equal 0, wiki_attachments.count
        assert_equal @asset.attachments.reload, wiki_attachments.reload
      end
    end

    context "#{upload_type} uploads: gists" do
      test "#{upload_type} uploads: creates attachments on Gist creation" do
        enable_feature_flag(:gist_attachment_scanning)

        env_settings.call

        contents = [
          { name: "file1.md", value: attachment_body_for(@asset) },
        ]

        gist = create_gist_with_attachments(@owner, contents)

        assert_equal 1, gist.attachments.count
        assert_equal @asset.attachments.reload, gist.attachments.reload

        att = @asset.attachments.first
        assert_equal @asset, att.asset
        assert_equal gist, att.attachable
        assert_equal gist.user, att.attacher
        assert_equal gist, att.entity
      end

      test "#{upload_type} uploads: creates attachments on Gist update" do
        enable_feature_flag(:gist_attachment_scanning)

        env_settings.call

        no_scan = save_file_for_uploadable(UserAsset.new(uploader: @uploader))
        gist = create_gist_with_attachments(@owner, [{ name: "file1.md", value: "no attachments" }])

        assert_equal 0, gist.attachments.count

        contents = [
          { name: "file1.md", value: attachment_body_for(@asset) },
        ]

        update_gist_with_attachments(gist, contents)

        assert_equal 1, gist.attachments.count
        assert_equal @asset.attachments.reload, gist.attachments.reload

        att = @asset.attachments.first
        assert_equal @asset, att.asset
        assert_equal gist, att.attachable
        assert_equal gist.user, att.attacher
        assert_equal gist, att.entity
      end

      test "#{upload_type} uploads: does not create attachments for deleted files" do
        enable_feature_flag(:gist_attachment_scanning)

        env_settings.call

        no_scan = save_file_for_uploadable(UserAsset.new(uploader: @uploader))
        gist = create_gist_with_attachments(@owner, [{ name: "file1.md", value: "no attachments" }])

        assert_equal 0, gist.attachments.count

        contents = [
          { name: "file1.md", value: attachment_body_for(@asset), delete: true },
        ]
        update_gist_with_attachments(gist, contents)

        assert_equal 0, gist.attachments.count
      end

      test "creates attachments for md files only" do
        enable_feature_flag(:gist_attachment_scanning)

        env_settings.call

        no_scan = save_file_for_uploadable(UserAsset.new(uploader: @uploader))
        contents = [
          { name: "file1.md", value: attachment_body_for(@asset) },
          { name: "file2.md", value: attachment_body_for(@asset2) },
          { name: "file3.txt", value: attachment_body_for(no_scan) },
        ]
        gist = create_gist_with_attachments(@owner, contents)

        assert_equal 2, gist.attachments.count
      end

      test "creates attachments for anonymous gists" do
        enable_feature_flag(:gist_attachment_scanning)

        env_settings.call

        contents = [
          { name: "file1.md", value: attachment_body_for(@asset) },
        ]
        gist = create_gist_with_attachments(nil, contents)

        assert_equal 1, gist.attachments.count
        assert_equal @asset.attachments.reload, gist.attachments.reload

        att = @asset.attachments.first
        assert_equal @asset, att.asset
        assert_equal gist, att.attachable
        assert_equal User.ghost, att.attacher
        assert_equal gist, att.entity
      end

      test "creates attachments for gist host based urls" do
        enable_feature_flag(:gist_attachment_scanning)
        env_settings.call
        gist_asset = save_file_for_uploadable(UserAsset.new(uploader: @uploader))
        gist_asset_2 = save_file_for_uploadable(UserAsset.new(uploader: @uploader))

        contents = [
          { name: "file1.md", value: attachment_body_for_gist(gist_asset) },
          { name: "file2.md", value: attachment_body_for_cluster_gist(gist_asset_2) },
        ]
        gist = create_gist_with_attachments(@uploader, contents)

        assert_equal 2, gist.attachments.count
        verify_attach = lambda do |gist_asset, gist|
          gist_asset_att = gist_asset.attachments.first
          assert_equal gist_asset, gist_asset_att.asset
          assert_equal gist, gist_asset_att.attachable
          assert_equal @uploader, gist_asset_att.attacher
          assert_equal gist, gist_asset_att.entity
        end
        verify_attach.call(gist_asset, gist)
        verify_attach.call(gist_asset_2, gist)
      end

      test "#{upload_type} uploads: does not remove attachments when not present in latest revision" do
        enable_feature_flag(:gist_attachment_scanning)

        env_settings.call

        contents = [
          { name: "file1.md", value: attachment_body_for(@asset) },
        ]

        gist = create_gist_with_attachments(@owner, contents)

        assert_equal 1, gist.attachments.count
        assert_equal @asset.attachments.reload, gist.attachments.reload

        contents = [
          { name: "file1.md", value: "no more attachment" },
        ]

        update_gist_with_attachments(gist, contents)

        assert_equal 1, gist.attachments.count
        assert_equal @asset.attachments.reload, gist.attachments.reload
      end

      test "does not create attachments when feature flag is disabled" do
        disable_feature_flag(:gist_attachment_scanning)

        env_settings.call

        contents = [
          { name: "file1.md", value: attachment_body_for(@asset) },
        ]

        gist = create_gist_with_attachments(@owner, contents)

        assert_equal 0, gist.attachments.count
        assert_equal @asset.attachments.reload, gist.attachments.reload
      end
    end

    context "#{upload_type} uploads: review comments" do
      test "doesn't attempt to re-attach asset unless body changes" do
        env_settings.call

        review_comment = build_attachment(PullRequestReviewComment, @asset, repository: nil, pull_request: @pull)
        assert_asset_attached do
          assert review_comment.save
          # `assert_asset_attached` needs the record returned from the block
          review_comment
        end

        PullRequestReviewComment.any_instance.expects(:attach_matching_assets).never
        review_comment.submit!

        PullRequestReviewComment.any_instance.expects(:attach_matching_assets).once
        review_comment.update(body: attachment_body_for(@asset, @asset2))
      end
    end
  end

  def assert_asset_attached_to(model, assets, attributes = nil)
    assert_asset_attached do
      record = create_attachment(model, assets, attributes)
      assert_kind_of model, record
      record
    end
  end

  def assert_asset_attached
    record = yield
    assert_equal 1, @asset.attachments.count
    assert_equal @asset.attachments.reload, record.attachments.reload

    att = @asset.attachments.first
    assert_equal @asset, att.asset
    assert_equal record, att.attachable
    assert_equal @author, att.attacher
  end

  def assert_repository_file_attached
    record = yield
    assert_equal 1, @repository_file.attachments.count
    assert_equal @repository_file.attachments.reload, record.attachments.reload

    att = @repository_file.attachments.first
    assert_equal @repository_file, att.asset
    assert_equal record, att.attachable
    assert_equal @author, att.attacher
  end

  def build_attachment(model, assets, attributes = nil)
    body = T.unsafe(self).attachment_body_for(*Array(assets))
    attr = { repository: @repo, user: @author, body: body }
    attr.update(attributes) if attributes
    attr.each_key do |key|
      attr.delete(key) unless attr[key]
    end

    build(model.name.underscore.to_sym, attr)
  end

  def build_video_attachment(model, video_assets, repository = @repo)
    body = video_attachment_body_for(video_assets)

    build(model.name.underscore.to_sym, { repository: repository, user: @author, body: body })
  end

  def build_file_attachment(model, repository_files, repository = @repo)
    body = file_attachment_body_for(repository_files)

    build(model.name.underscore.to_sym, { repository: repository, user: @author, body: body })
  end

  def create_attachment(model, assets, attributes = nil)
    model_instance = build_attachment(model, assets, attributes)
    # Note: The conditions are intentionally kept separate for clarity.
    # This approach describe the jobs required for each model.
    if model == PullRequestReview || model == GistComment
      perform_enqueued_jobs(only: [AttachMatchingAssetsJob]) { model_instance.tap(&:save!) }
    elsif model == IssueComment
      perform_enqueued_jobs(only: [IssueCommentOrchestration.job_class]) do
        model_instance.tap(&:save!)
      end
    elsif model == Issue
      perform_enqueued_jobs(only: [IssueOrchestration.job_class, AttachMatchingAssetsJob]) do
        model_instance.tap(&:save!)
      end
    else
      model_instance.tap(&:save!)
    end
  end

  def create_gist_with_attachments(user, contents)
    perform_enqueued_jobs(only: [AttachMatchingAssetsJob]) do
      GistHelpers.generate(user: user, contents: contents)
    end
  end

  def update_gist_with_attachments(gist, contents)
    perform_enqueued_jobs(only: [AttachMatchingAssetsJob]) do
      gist.update!(contents: contents)
    end
  end

  def attachment_body_for(*assets)
    bodies = assets.map do |asset|
      "yo ![](#{asset.storage_external_url}) ![](foo.jpg)"
    end
    bodies.join("\n")
  end

  def attachment_body_for_gist(*assets)
    bodies = assets.map do |asset|
      "yo ![](#{GitHub.gist_url}/user-attachments/assets/#{asset.guid}}) ![](foo.jpg)"
    end
    bodies.join("\n")
  end

  def attachment_body_for_cluster_gist(*assets)
    bodies = assets.map do |asset|
      user = asset.uploader
      "yo ![](#{GitHub.gist_url}/assets/#{user.id}/#{asset.guid}}) ![](foo.jpg)"
    end
    bodies.join("\n")
  end

  def video_attachment_body_for(*assets)
    assets.map { |asset| "#{asset.storage_external_url}" }.join("\n")
  end

  def file_attachment_body_for(*assets)
    assets.map { |asset| "[#{asset.name}](#{asset.permalink})" }.join("\n")
  end

  def setup_allowed_hosts
    hosts = [Addressable::URI.parse(GitHub.user_images_cdn_url).host]
    if GitHub::Goomba::VideoTagFilter.instance_variable_defined?(:@video_host_allowlist)
      GitHub::Goomba::VideoTagFilter.remove_instance_variable(:@video_host_allowlist)
    end
    GitHub::Goomba::VideoTagFilter.stubs(:video_host_allowlist).returns(hosts)
  end
end
