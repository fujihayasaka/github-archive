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

    @asset = save_file_for_uploadable(UserAsset.new(uploader: @uploader))
    @asset2 = save_file_for_uploadable(UserAsset.new(uploader: @uploader))
    @video_asset = save_file_for_uploadable(UserAsset.new(uploader: @uploader), name: "vid.mp4", content_type: "video/mp4")
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

    test "#{upload_type} uploads: adds attachments on update" do
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

  def create_attachment(model, assets, attributes = nil)
    model_instance = build_attachment(model, assets, attributes)
    # Note: The conditions are intentionally kept separate for clarity.
    # This approach describe the jobs required for each model.
    if model == PullRequestReview
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

  def attachment_body_for(*assets)
    bodies = assets.map do |asset|
      "yo ![](#{asset.storage_external_url}) ![](foo.jpg)"
    end
    bodies.join("\n")
  end

  def video_attachment_body_for(*assets)
    assets.map { |asset| "#{asset.storage_external_url}" }.join("\n")
  end

  def setup_allowed_hosts
    hosts = [Addressable::URI.parse(GitHub.user_images_cdn_url).host]
    if GitHub::Goomba::VideoTagFilter.instance_variable_defined?(:@video_host_allowlist)
      GitHub::Goomba::VideoTagFilter.remove_instance_variable(:@video_host_allowlist)
    end
    GitHub::Goomba::VideoTagFilter.stubs(:video_host_allowlist).returns(hosts)
  end
end
