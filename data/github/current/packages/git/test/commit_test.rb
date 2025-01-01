# typed: true
# frozen_string_literal: true

require "test_helper"

module CommitSharedTests
  extend T::Helpers

  requires_ancestor { GitHub::TestCase }

  def test_mentioned_users
    commit_info = {
      "oid"       => @commit_oid,
      "type"      => "commit",
      "message"   => "space change @#{@collab.login}",
      "parents"   => ["c3956841a7cb7e8ba4a6fd923568d86958f01573"],
      "tree"      => "d9d67f971d948d0b43f1d91ead123e0b969556fe",
      "committer" => ["rick", "technoweenie@gmail.com", "2010-04-28T16:20:56Z"],
      "author"    => ["rick", "technoweenie@gmail.com", "2010-04-28T16:20:56Z"],
      "encoding"  => "UTF-8",
    }

    commit = Commit.new(@repo, commit_info)

    assert_equal [@collab], commit.mentioned_users
  end

  def test_author_and_committer
    assert_equal @committer, @commit.author
    assert_equal @committer, @commit.committer
  end

  def test_async_authors_contains_just_the_author_when_there_are_no_co_authors
    assert_equal [@commit.author], @commit.async_authors.sync
  end

  def test_author_and_committer_with_no_matching_user
    @committer.email_roles.delete_all
    @committer.emails.destroy_all

    assert_nil @commit.author
    assert_nil @commit.committer
  end

  def test_assigning_author_and_committer
    assert_equal @other_committer, (@commit.author = @other_committer)
    assert_equal @other_committer, (@commit.committer = @other_committer)
  end

  def test_sets_message_context
    commit = @simple.commits.find("63611721afd41f58f801d66e543d8288b4c5eb44")
    context = commit.message_context

    assert_equal @simple, context[:entity]
    assert_equal @committer, context[:current_user]
  end

  def test_github_committer_is_ignored_when_deciding_the_context_user
    metadata = {
      message: "change stuff",
      committer: {
        name: GitHub.web_committer_name,
        email: GitHub.web_committer_email,
      },
      author: @owner,
    }
    commit = Spokesd.with_spokesd_disabled { @repo.heads.find("master").append_commit(metadata, @owner) }

    assert_equal @github, commit.committer
    context = commit.message_context
    assert_equal @repo, context[:entity]
    assert_equal @owner, context[:current_user]
  end

  def test_commenters
    comment = create :commit_comment, user: @owner, repository: @repo,
      commit_id: @commit.oid

    assert @commit.comments?
    assert_equal [@owner], @commit.commenters
  end

  def test_participants
    comment = create :commit_comment, user: @owner, repository: @repo,
      commit_id: @commit.oid

    assert @commit.comments?
    assert_equal [@committer, @owner], @commit.participants
  end

  def test_check_if_commit_is_lockable_by_user
    refute @commit.locked?

    @commit.lock(@committer)
    refute @commit.locked?

    @commit.lock(@collab)
    assert @commit.locked?

    @commit.unlock(@committer)
    assert @commit.locked?

    @commit.unlock(@collab)
    refute @commit.locked?
  end

  def test_commit_message_with_co_authored_by_trailer
    commit = Commit.new @repo, @commit_info_with_dup_user

    assert_equal 3, commit.author_actors.size
    assert_equal commit.author_actor.name, commit.author_actors[0].name
    assert_equal commit.author_actor.email, commit.author_actors[0].email
    assert_equal "Matt Clark", commit.author_actors[1].name
    assert_equal "mclark@github.com", commit.author_actors[1].email
    assert_equal "Matthew", commit.author_actors[2].name
    assert_equal "watership@down.com", commit.author_actors[2].email

    authors = commit.async_authors.sync
    assert_equal 2, authors.size
    assert_equal commit.author, authors[0]
    assert_equal @other_user, authors[1]
  end

  def test_async_unique_visible_author_actors
    commit_info = @commit_info_with_dup_user.dup
    signatures = commit_info["trailers"]["co-authored-by"].dup + ["Rando Calrissian <rando@cloudcity.com>"] * 2
    commit_info["trailers"] = { "co-authored-by" => signatures }

    commit = Commit.new @repo, commit_info

    actors = commit.async_unique_visible_author_actors(@other_user).sync

    assert_equal 3, actors.length
    assert_equal commit.author_actor.name, commit.author_actors[0].name
    assert_equal commit.author_actor.email, commit.author_actors[0].email
    assert_equal "Matt Clark", actors[1].name
    assert_equal "mclark@github.com", actors[1].email
    assert_equal "Rando Calrissian", actors[2].name
    assert_equal "rando@cloudcity.com", actors[2].email
  end

  def test_commit_message_with_bad_co_authored_by_trailer
    info = @commit_info_with_co_authors.dup
    info["trailers"] = { "co-authored-by" => ["Invalid N<me", "Matt Clark <mclark@github.com>"] }
    commit = Commit.new @repo, info

    assert_equal 2, commit.author_actors.size
    assert_equal commit.author_actor.name, commit.author_actors[0].name
    assert_equal commit.author_actor.email, commit.author_actors[0].email
    assert_equal "Matt Clark", commit.author_actors[1].name
    assert_equal "mclark@github.com", commit.author_actors[1].email
  end

  def test_commit_message_with_whitespaces_co_authored_by_trailer
    info = @commit_info_with_co_authors.dup
    info["trailers"] = { "co-authored-by" => [
      "Octo   Cat   <octocat@github.com>", # whitespace in the middle
      " Gordey Doronin <gordey4doronin@github.com>", # whitespace at the beginning
      "Matt Clark <mclark@github.com> ", # whitespace at the end
    ] }
    commit = Commit.new @repo, info

    assert_equal 4, commit.author_actors.size
    assert_equal commit.author_actor.name, commit.author_actors[0].name
    assert_equal commit.author_actor.email, commit.author_actors[0].email
    assert_equal "Octo   Cat", commit.author_actors[1].name
    assert_equal "octocat@github.com", commit.author_actors[1].email
    assert_equal "Gordey Doronin", commit.author_actors[2].name
    assert_equal "gordey4doronin@github.com", commit.author_actors[2].email
    assert_equal "Matt Clark", commit.author_actors[3].name
    assert_equal "mclark@github.com", commit.author_actors[3].email
  end

  def test_async_authored_by_committer_with_author_and_committer_matching
    commit = Commit.new @repo, @commit_info
    assert commit.async_authored_by_committer?.sync
  end

  def test_async_authored_by_committer_with_author_and_committer_not_matching
    info = @commit_info.dup
    info["committer"] = ["Matt Clark", "mclark@github.com", "2010-04-28T16:20:56Z"]

    commit = Commit.new @repo, info
    refute commit.async_authored_by_committer?.sync
  end

  def test_async_authored_by_committer_with_committer_matching_a_co_author
    commit = Commit.new @repo, @commit_info_with_co_authors
    assert commit.async_authored_by_committer?.sync
  end

  def test_async_authored_by_committer_with_committer_email_matching_a_co_author_email
    @committer.email_roles.delete_all
    @committer.emails.destroy_all
    @other_user.email_roles.delete_all
    @other_user.emails.destroy_all

    commit = Commit.new @repo, @commit_info_with_co_authors
    assert commit.async_authored_by_committer?.sync
  end

  def test_async_authored_by_committer_with_no_user_and_matching_emails
    info = @commit_info.dup
    info["committer"] = ["Some User", "some@user.com", "2010-04-28T16:20:56Z"]
    info["author"]    = ["Different Name", "some@user.com", "2010-04-28T16:20:56Z"]

    commit = Commit.new @repo, info
    assert commit.async_authored_by_committer?.sync
  end

  def test_async_authored_by_committer_with_no_user_and_mismatching_emails
    info = @commit_info.dup
    info["committer"] = ["Some User", "some@user.com", "2010-04-28T16:20:56Z"]
    info["author"]    = ["Some User", "other@user.com", "2010-04-28T16:20:56Z"]

    commit = Commit.new @repo, info
    refute commit.async_authored_by_committer?.sync
  end

  def test_committed_via_web_is_true_when_committed_on_github
    info = @commit_info.dup
    info["committer"] = [GitHub.web_committer_name, GitHub.web_committer_email, "2010-04-28T16:20:56Z"]
    commit = Commit.new @repo, info

    assert commit.committed_via_web?
  end

  def test_committed_via_web_is_false_when_not_committed_on_github
    commit = Commit.new @repo, @commit_info
    refute commit.committed_via_web?
  end
end

class CommitTest < GitHub::TestCase
  include CommitSharedTests

  include GpgKeyHelper

  fixtures do
    @owner          = create(:user, plan: :medium)
    @repo           = create(:repository, owner: @owner)
    @simple         = create(:repository)
    @messages       = create(:repository)

    @collab = create(:user)
    @repo.add_member(@collab)
    @collab.watch_repo(@repo)

    @committer = create(:user, email: "technoweenie@gmail.com", name: "technoweenie")
    @other_committer = create(:user, email: "simon@rozet.name", name: "sr")

    @other_user = create(:user, email: "mclark@github.com")
    @other_user.emails.create!(email: "watership@down.com")

    @github = create(:user, email: GitHub.web_committer_email)

    @commit_oid  = "3572d83ba062076f6a740379463d0f3f770d7fc5"
    @commit_info = {
      "oid"       => @commit_oid,
      "type"      => "commit",
      "message"   => "space change",
      "parents"   => ["c3956841a7cb7e8ba4a6fd923568d86958f01573"],
      "tree"      => "d9d67f971d948d0b43f1d91ead123e0b969556fe",
      "committer" => ["rick", "technoweenie@gmail.com", "2010-04-28T16:20:56Z"],
      "author"    => ["rick", "technoweenie@gmail.com", "2010-04-28T16:20:56Z"],
      "encoding"  => "UTF-8",
    }

    @commit_info_timestamp = {
      "oid"       => @commit_oid,
      "type"      => "commit",
      "message"   => "space change",
      "parents"   => ["c3956841a7cb7e8ba4a6fd923568d86958f01573"],
      "tree"      => "d9d67f971d948d0b43f1d91ead123e0b969556fe",
      "committer" => ["rick", "technoweenie@gmail.com", [1398662456, 39600]],
      "author"    => ["rick", "technoweenie@gmail.com", [1398662456, 39600]],
      "encoding"  => "UTF-8",
    }
    @commit_info_melbourne = {
      "oid"       => @commit_oid,
      "type"      => "commit",
      "message"   => "space change",
      "parents"   => ["c3956841a7cb7e8ba4a6fd923568d86958f01573"],
      "tree"      => "d9d67f971d948d0b43f1d91ead123e0b969556fe",
      "committer" => ["rick", "technoweenie@gmail.com", "2014-04-28T16:20:56+11:00"],
      "author"    => ["rick", "technoweenie@gmail.com", "2014-04-28T16:20:56+11:00"],
      "encoding"  => "UTF-8",
    }
    @commit_info_amsterdam = {
      "oid"       => @commit_oid,
      "type"      => "commit",
      "message"   => "space change",
      "parents"   => ["c3956841a7cb7e8ba4a6fd923568d86958f01573"],
      "tree"      => "d9d67f971d948d0b43f1d91ead123e0b969556fe",
      "committer" => ["rick", "technoweenie@gmail.com", "2014-04-28T16:20:56+01:00"],
      "author"    => ["rick", "technoweenie@gmail.com", "2014-04-28T16:20:56+01:00"],
      "encoding"  => "UTF-8",
    }
    @commit_info_pacific = {
      "oid"       => @commit_oid,
      "type"      => "commit",
      "message"   => "space change",
      "parents"   => ["c3956841a7cb7e8ba4a6fd923568d86958f01573"],
      "tree"      => "d9d67f971d948d0b43f1d91ead123e0b969556fe",
      "committer" => ["rick", "technoweenie@gmail.com", "2014-04-28T16:20:56-08:00"],
      "author"    => ["rick", "technoweenie@gmail.com", "2014-04-28T16:20:56-08:00"],
      "encoding"  => "UTF-8",
    }

    invalid_encoded_name = Marshal.load("\x04\bI\"\x19\xEC\x83\xA4\xEC\x9D\xB4\xEB\x8B?(\xEA\xB9\x80\xEC\xA7\x80\xED\x9B?)\x06:\rencoding\"\nCP949")

    @commit_info_bad_encoding = {
      "oid"       => @commit_oid,
      "type"      => "commit",
      "message"   => <<~MSG,
        space change

        co-authored-by: #{invalid_encoded_name} <mclark@github.com>
      MSG
      "parents"   => ["c3956841a7cb7e8ba4a6fd923568d86958f01573"],
      "tree"      => "d9d67f971d948d0b43f1d91ead123e0b969556fe",
      "committer" => [invalid_encoded_name, "nogood@gmail.com", "2010-04-28T16:20:56Z"],
      "author"    => [invalid_encoded_name, "nogood@gmail.com", "2010-04-28T16:20:56Z"],
      "encoding"  => "UTF-8",
      "trailers"  => {
        "co-authored-by" => ["#{invalid_encoded_name} <mclark@github.com>"],
      },
    }

    @commit_info_message_iso_8859_1_encoding = {
      "oid"       => @commit_oid,
      "type"      => "commit",
      "message"   => <<~MSG,
        Fu\xdfg\xe4nger\xfcberg\xe4nge
      MSG
      "parents"   => ["c3956841a7cb7e8ba4a6fd923568d86958f01573"],
      "tree"      => "d9d67f971d948d0b43f1d91ead123e0b969556fe",
      "committer" => [invalid_encoded_name, "nogood@gmail.com", "2010-04-28T16:20:56Z"],
      "author"    => [invalid_encoded_name, "nogood@gmail.com", "2010-04-28T16:20:56Z"],
      "encoding"  => "ISO-8859-1",
      "trailers"  => {
        "co-authored-by" => ["#{invalid_encoded_name} <mclark@github.com>"],
      },
    }

    @commit_info_mentions_commit_without_pre_expanded_shas = {
      "oid"       => @commit_oid,
      "type"      => "commit",
      "message"   => "space change c395684 abcd1234",
      "parents"   => ["c3956841a7cb7e8ba4a6fd923568d86958f01573"],
      "tree"      => "d9d67f971d948d0b43f1d91ead123e0b969556fe",
      "committer" => ["rick", "technoweenie@gmail.com", "2010-04-28T16:20:56Z"],
      "author"    => ["rick", "technoweenie@gmail.com", "2010-04-28T16:20:56Z"],
      "encoding"  => "UTF-8",
    }

    @commit_info_mentions_commit_with_pre_expanded_shas = {
      "oid"       => @commit_oid,
      "type"      => "commit",
      "message"   => "space change c395684 abcd1234",
      "message_shas" => { "abcd1234" => "abcd1234abcd1234abcd1234abcd1234abcd1234" },
      "parents"   => ["c3956841a7cb7e8ba4a6fd923568d86958f01573"],
      "tree"      => "d9d67f971d948d0b43f1d91ead123e0b969556fe",
      "committer" => ["rick", "technoweenie@gmail.com", "2010-04-28T16:20:56Z"],
      "author"    => ["rick", "technoweenie@gmail.com", "2010-04-28T16:20:56Z"],
      "encoding"  => "UTF-8",
    }

    @commit_info_with_co_authors = {
      "oid"       => @commit_oid,
      "type"      => "commit",
      "message"   => <<~MSG,
        our sweet 🍐ing change

        co-authored-by: Matt Clark <mclark@github.com>
      MSG
      "message_shas" => { "abcd1234" => "abcd1234abcd1234abcd1234abcd1234abcd1234" },
      "parents"   => ["c3956841a7cb7e8ba4a6fd923568d86958f01573"],
      "tree"      => "d9d67f971d948d0b43f1d91ead123e0b969556fe",
      "committer" => ["Matt Clark", "mclark@github.com", "2010-04-28T16:20:56Z"],
      "author"    => ["rick", "technoweenie@gmail.com", "2010-04-28T16:20:56Z"],
      "encoding"  => "UTF-8",
      "trailers"  => {
        "co-authored-by" => 2.times.map { "Matt Clark <mclark@github.com>" },
      },
    }

    @commit_info_with_dup_user = @commit_info_with_co_authors.dup
    @commit_info_with_dup_user["trailers"] = {
      "co-authored-by" => @commit_info_with_dup_user["trailers"]["co-authored-by"].dup << "Matthew <watership@down.com>",
    }

    @signed = create(:repository)
    @signing_key = create_gpg_key
    @user = @signing_key.user
    @other_signing_key = create_gpg_key("two")

    smime_ca = FakeCA.new("/CN=root1")
    @smime_cert = smime_ca.issue("/CN=#{@user.login}/emailAddress=#{@user.emails.verified.first.email}").freeze
    GitHub.git_signing_smime_cert_store.add_cert(smime_ca.parsed)
  end

  setup do
    Spokesd.enable_spokesd

    example_repo :commit_test, @repo
    example_repo :simple, @simple
    example_repo :messages, @messages
    example_repo :signed_commits, @signed

    @smime_commit_oid = Spokesd.with_spokesd_disabled { @smime_cert.create_signed_commit(@signed, @user) }
    @smime_commit = @signed.commits.find(@smime_commit_oid)
    @signed_signature = Platform::Loaders::GitSignature.load(@smime_commit)

    reset_cache
    reset_monolith_redis_rate_limiter

    @commit = Commit.new(@repo, @commit_info)
    @commit_timestamp = Commit.new(@repo, @commit_info_timestamp)
    @commit_melbourne = Commit.new(@repo, @commit_info_melbourne)
    @commit_amsterdam = Commit.new(@repo, @commit_info_amsterdam)
    @commit_pacific = Commit.new(@repo, @commit_info_pacific)
  end

  test "#oid et al" do
    assert_equal @commit_oid, @commit.oid
    assert_equal @commit_oid, @commit.sha
    assert_equal @commit_oid, "#{@commit}"
  end

  test "equality" do
    assert_equal @commit, @commit.dup
    assert_equal @commit, @repo.commits.find(@commit_oid)
    assert_equal @commit, Commit.new(@repo, @commit_info)

    refute_equal @commit, Commit.new(create(:repository), @commit_info)

    refute_equal @commit, @repo.commits.find(@commit.parent_oids.first)

    fake = Struct.new(:oid).new(@commit.oid)
    refute_equal @commit, fake
  end

  test "hash identity" do
    val = Object.new
    hash = { @commit => val }

    assert_equal val, hash[@commit]
    assert_equal val, hash[@commit.dup]
    assert_equal val, hash[Commit.new(@repo, @commit_info)]

    refute_equal val, hash[Commit.new(create(:repository), @commit_info)]

    hash[@commit.dup] = "x"

    assert_equal [@commit], hash.keys

    parent_commit = @repo.commits.find(@commit.parent_oids.first)

    hash[parent_commit] = val

    expected = { @commit => "x", parent_commit.dup => val }
    assert_equal expected, hash

    fake = Struct.new(:oid).new(@commit.oid)
    assert_nil hash[fake]
    assert_nil hash[@commit.oid]
  end

  test "#id blows up" do
    assert_raises(NoMethodError) { @commit.id }
  end

  test "commit info attributes" do
    assert_equal @commit_info["parents"], @commit.parent_oids
    assert_equal @commit_info["tree"], @commit.tree_oid
    assert_equal @commit_info["message"], @commit.message

    assert_equal @commit_info["author"][0], @commit.author_name
    assert_equal @commit_info["author"][1], @commit.author_email
    assert_equal Time.iso8601(@commit_info["author"][2]), @commit.authored_date

    assert_equal [@commit.author_name],  @commit.author_names
    assert_equal [@commit.author_email], @commit.author_emails

    assert_equal @commit_info["committer"][0], @commit.committer_name
    assert_equal @commit_info["committer"][1], @commit.committer_email
    assert_equal Time.iso8601(@commit_info["committer"][2]), @commit.committed_date
  end

  test "commit info attributes including co-authors" do
    commit = Commit.new @repo, @commit_info_with_co_authors

    assert_equal [@commit.author_name, "Matt Clark"], commit.author_names
    assert_equal [@commit.author_email, "mclark@github.com"], commit.author_emails
  end

  test "commit info attributes including co-authors that duplicate the author email" do
    commit_info = @commit_info_with_co_authors.dup
    commit_info["trailers"] = { "co-authored-by" => commit_info["trailers"]["co-authored-by"].dup << "Doppelgänger <technoweenie@gmail.com>" }
    commit = Commit.new @repo, commit_info

    assert_equal [@commit.author_name, "Matt Clark"], commit.author_names
    assert_equal [@commit.author_email, "mclark@github.com"], commit.author_emails
  end

  test "commit info timezone aware attributes" do
    assert_equal 39600, @commit_timestamp.authored_date.utc_offset
    assert_equal 39600, @commit_timestamp.committed_date.utc_offset
    assert_equal Date.new(2014, 4, 28), @commit_timestamp.contributed_on

    assert_equal 39600, @commit_melbourne.authored_date.utc_offset
    assert_equal 39600, @commit_melbourne.committed_date.utc_offset
    assert_equal Date.new(2014, 4, 28), @commit_melbourne.contributed_on

    assert_equal 3600, @commit_amsterdam.authored_date.utc_offset
    assert_equal 3600, @commit_amsterdam.committed_date.utc_offset
    assert_equal Date.new(2014, 4, 28), @commit_amsterdam.contributed_on

    assert_equal -28800, @commit_pacific.authored_date.utc_offset
    assert_equal -28800, @commit_pacific.committed_date.utc_offset
    assert_equal Date.new(2014, 4, 28), @commit_pacific.contributed_on
  end

  test "#assign_attributes doesn't blow up when bad hex characters show up in the author/committer/co-author info" do
    assert Commit.new(@repo, @commit_info_bad_encoding)
  end

  test "#abbreviated_oid" do
    assert_equal @commit_oid[0, 7], @commit.abbreviated_oid
  end

  test ".prefill_short_messages" do
    with_cache_enabled do
      commit = Commit.new(@repo, @commit_info_with_co_authors)
      Commit.prefill_short_messages([commit])
      assert_predicate commit.async_short_message_html, :fulfilled?

      # reload to ensure loading from memcache works
      commit = Commit.new(@repo, @commit_info_with_co_authors)
      Commit.prefill_short_messages([commit])
      assert_predicate commit.async_short_message_html, :fulfilled?
    end
  end

  test "#merge_commit?" do
    assert !@commit.merge_commit?
    @commit.parent_oids += ["deadbeedeadbeedeadbeedeadbeedeadbeedeadb"]
    assert @commit.merge_commit?
  end

  test "#empty_message?" do
    assert !@commit.empty_message?

    @commit.message = ""
    assert @commit.empty_message?

    @commit.message = "    "
    assert @commit.empty_message?

    @commit.message = " \n "
    assert @commit.empty_message?
  end

  test "#short_message_html with non-ASCII characters" do
    issue  = create(:issue,
      repository: @simple,
      user: @committer,
      number: "42",
      title: "test",
    )
    commit = @simple.commits.find("63611721afd41f58f801d66e543d8288b4c5eb44")
    commit.message = "Don’t write CC: line on zwrite -C ''"
    assert_equal "Don’t write CC: line on zwrite -C ''", commit.short_message_html
  end

  test "#message_body_html with a proper git message" do
    commit = @messages.commits.find("0f4b2ba0b3312a619c3022c2f03c3fdc8f6c664a")
    desc = %{Some more tweaks here:

- Do not use `strftime`, because it's not assured
to be cross-platform

- Use C-like string formatting for Great Glory
When Printing Numbers.

- Always print an email address -- even if we don't
have one. A missing email field will crash `fsck`.}

    assert_equal_html desc, commit.message_body_html
  end

  test "#message_body_html with no blank newline" do
    commit = @messages.commits.find("b6b5c0707eb2d964195ef38bc4f45c5ede134d79")
    desc = %{They just keep adding new lines here like it was no big deal. Almost like
the whole thing should be wrapped at 80 chars.}

    assert_equal desc, commit.message_body_html
  end

  test "#message_body_html when people don't believe in newlines" do
    commit = @messages.commits.find("586265f50ac184bda9b1961ef2eef59341e09613")
    desc = %{…e who doesn't love someone like that? Did I ever tell you about my daughter Sansa? Honestly, I wish someone would just do away with her. Constantly blab blab blabbing on about absolutely *nothing*. Wish she'd grow some testicles.}

    assert_equal_html desc, commit.message_body_html
  end

  test "#message_body_html when there is an invalid UTF-8 byte sequence" do
    commit = @messages.commits.find("f3f3573f59d986c7fd3c0ac8fc4414111a483018")
    assert_equal "", commit.message_body_html
  end

  test "short_message returns nil when commit message is empty" do
    commit = @simple.commits.find("cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24")
    assert commit.empty_message?
    assert_nil commit.short_message
    assert_equal "", commit.message_body_html
  end

  test "message_body_html returns empty string when commit message is empty" do
    commit = @simple.commits.find("cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24")
    assert commit.empty_message?
    assert_equal "", commit.message_body_html
  end

  context "#async_truncated_message_body_html" do
    test "doesn't truncate if visible content is less than or equal to the limit" do
      commit = @messages.commits.find("b6b5c0707eb2d964195ef38bc4f45c5ede134d79")
      message = %{They just keep adding new lines here like it was no big deal. Almost like
the whole thing should be wrapped at 80 chars.}
      limit = 200

      truncated_body_html = commit.async_truncated_message_body_html(limit).sync

      assert_equal "<p>#{message}</p>", truncated_body_html
    end

    test "truncates if visible content is more than the limit" do
      commit = @messages.commits.find("b6b5c0707eb2d964195ef38bc4f45c5ede134d79")
      limit = 20

      truncated_body_html = commit.async_truncated_message_body_html(limit).sync

      assert_equal "<p>They just keep ad…</p>", truncated_body_html
    end
  end

  test "#stats" do
    stats = @commit.stats
    assert_equal 1, stats.additions
    assert_equal 1, stats.deletions
    assert_equal 2, stats.total
  end

  test "#diff" do
    assert_equal 1, @commit.diff.size
  end

  test "#comments with no comments" do
    assert !@commit.comments?
    assert_equal 0, @commit.comment_count
    assert_equal [], @commit.comments
  end

  test "#comments with 1 commit comment" do
    comment = create :commit_comment, user: @owner, repository: @repo,
      commit_id: @commit.oid

    assert @commit.comments?
    assert_equal 1, @commit.comment_count
  end

  test "#comments with out of order commit comments get returned sorted by created_at" do
    comment = create :commit_comment, user: @owner, repository: @repo,
      commit_id: @commit.oid, created_at: DateTime.parse("2015-10-22")

    comment2 = create :commit_comment, user: @owner, repository: @repo,
    commit_id: @commit.oid, created_at: DateTime.parse("2015-10-21")

    assert @commit.comments?
    assert_equal 2, @commit.comment_count
    assert_equal [comment2, comment], @commit.comments
  end

  test "#participants returns a user who only has access to this repo through a child team of a team that's directly assigned to it" do
    org = create(:organization, admin: @owner)
    @repo.toggle_visibility(actor: @owner)

    team = create(:team, organization: org, privacy: :closed)
    team.add_repository(@repo, :pull, allow_different_owner: true)
    child_team = create(:team, organization: org, privacy: :closed, parent_team_id: team.id)
    commenter_user = create(:user)
    child_team.add_member(commenter_user)

    create(:commit_comment, user: commenter_user, repository: @repo, commit_id: @commit.oid)

    @repo.reload
    assert @commit.participants.include?(commenter_user)
  end

  test "#inspect" do
    assert_equal "#<Commit oid: \"#{@commit_oid}\", created_at: \"#{@commit.created_at}\", repository_id: \"#{@commit.repository.id}\", repository_type: \"#{@commit.repository.class.name}\">", @commit.inspect

    # we test for a nil repo here because `inspect` is such a low level method that it may even
    # be called on commits in an invalid state.
    commit = Commit.new(@repo, @commit_info)
    commit.instance_variable_set(:@repository, nil)
    assert_equal "#<Commit oid: \"#{commit.oid}\", created_at: \"#{commit.created_at}\", repository_id: \"\", repository_type: \"NilClass\">", commit.inspect
  end

  test "#latest_deployment" do
    deployment = @repo.deployments.create(ref: "master",
                                           sha: @commit.oid,
                                           creator: @owner)

    deployment.statuses.create(state: "pending",
                               creator: @owner,
                               log_url: "https://a.com",
                               description: "Trying to deploy!")
    deployment.statuses.create(state: "success",
                               creator: @owner,
                               log_url: "https://a.com",
                               description: "Successfully deployed stuff!")

    latest_deployment = @commit.latest_deployment
    assert_equal deployment.id, latest_deployment.id
    latest_status = latest_deployment.statuses.first

    assert_equal "success", latest_status.state
    assert_equal "https://a.com", latest_status.log_url
    assert_equal "Successfully deployed stuff!", latest_status.description
  end

  test "check if user can comment on commit" do
    installation = make_integration_installation(repository: @repo, permissions: { "contents" => :read })

    assert @commit.can_comment?(@collab)
    assert @commit.can_comment?(@committer)
    assert @commit.can_comment?(installation.bot)

    @commit.lock(@collab)

    assert @commit.can_comment?(@collab)
    refute @commit.can_comment?(installation.bot)
    refute @commit.can_comment?(@committer)
  end

  test "commit is readable and unlocked for users with read access to the repo" do
    assert @commit.readable_and_unlocked_for?(@committer)
  end

  test "commit is not readable and unlocked for non-users" do
    refute @commit.readable_and_unlocked_for?(create(:organization))
  end

  test "commit is not readable and unlocked when the commit is locked" do
    @commit.lock(@collab)

    refute @commit.readable_and_unlocked_for?(@committer)
  end

  test "commit is not readable and unlocked when the repository is not readable by the user" do
    private_repo = create :private_repository

    commit_info = {
      "oid"       => @commit_oid,
      "type"      => "commit",
      "message"   => "some change",
      "parents"   => ["c3956841a7cb7e8ba4a6fd923568d86958f01573"],
      "tree"      => "d9d67f971d948d0b43f1d91ead123e0b969556fe",
      "committer" => ["rick", "technoweenie@gmail.com", "2010-04-28T16:20:56Z"],
      "author"    => ["rick", "technoweenie@gmail.com", "2010-04-28T16:20:56Z"],
      "encoding"  => "UTF-8",
    }

    commit = Commit.new(private_repo, commit_info)

    refute commit.readable_and_unlocked_for?(@committer)
  end

  test "lock commit comments" do
    refute @commit.locked?
    @commit.lock(@collab)
    assert @commit.locked?
  end

  test "unlock commit comments" do
    @commit.lock(@collab)
    assert @commit.locked?

    @commit.unlock(@collab)
    refute @commit.locked?
  end

  test "commit message encoded with ISO-8859-1" do
    commit = Commit.new @repo, @commit_info_message_iso_8859_1_encoding

    assert_equal "Fußgängerübergänge", commit.message
  end

  test "commit message without pre-expanded shas" do
    commit = Commit.new @repo, @commit_info_mentions_commit_without_pre_expanded_shas
    referenced_oid = "c3956841a7cb7e8ba4a6fd923568d86958f01573"
    # Check that the real short sha gets expanded.

    commit_url = "#{GitHub.url}/#{@repo.nwo}/commit/#{referenced_oid}"
    hovercard_attributes = HovercardsTestHelper.commit_hovercard_attributes(commit_url: commit_url)
    expected = "space change <a class=\"commit-link\" #{hovercard_attributes} href=\"#{commit_url}\"><tt>#{referenced_oid[0, 7]}</tt></a> abcd1234"
    assert_dom_equal expected, commit.short_message_html
  end

  test "commit message with pre-expanded shas" do
    commit = Commit.new @repo, @commit_info_mentions_commit_with_pre_expanded_shas
    # Check that the expanded fake commit is the only one with a link,
    # which shows that the HTML renderer didn't ask to expand shas separately.
    assert_match /space change c395684 <a.*abcd1234abcd1234/,
      commit.short_message_html, "HTML pipeline should use commit shas that came back with the commit info"
  end

  test "#async_notifications_list returns Repository" do
    assert @repo, @commit.async_notifications_list.sync
  end

  context "on-behalf-of trailer" do
    test "valid commit message with valid trailer signed by an org member" do
      verified_domain = "verified.com"
      org = create(:organization)
      create(:verifiable_domain, owner: org, verified: true, domain: verified_domain)
      author = create(:user, email: "author@#{verified_domain}")
      org.add_member(author)
      committer = create(:user, email: "committer@#{verified_domain}")
      org.add_member(committer)

      info = @commit_info_with_co_authors.dup
      info["committer"] = [committer.login, committer.email, "2010-04-28T16:20:56Z"]
      info["author"] = [author.login, author.email, "2010-04-28T16:20:56Z"]
      info["trailers"] = { "on-behalf-of" => ["#{org.login} <org@#{verified_domain}>"] }
      commit = Commit.new @repo, info
      Platform::Loaders::GitSignature.expects(:load).with(commit).returns(@signed_signature)

      assert_equal org, commit.async_on_behalf_of.sync
    end

    test "valid commit message with valid trailer signed by github" do
      verified_domain = "verified.com"
      org = create(:organization)
      create(:verifiable_domain, owner: org, verified: true, domain: verified_domain)
      author = create(:user, email: "author@#{verified_domain}")
      org.add_member(author)

      info = @commit_info_with_co_authors.dup
      info["committer"] = ["github", GitHub.web_committer_email, "2010-04-28T16:20:56Z"]
      info["author"] = [author.login, author.email, "2010-04-28T16:20:56Z"]
      info["trailers"] = { "on-behalf-of" => ["#{org.login} <org@#{verified_domain}>"] }
      commit = Commit.new @repo, info
      Platform::Loaders::GitSignature.expects(:load).with(commit).returns(@signed_signature)

      assert_equal org, commit.async_on_behalf_of.sync
    end

    test "commit message with invalid org email" do
      verified_domain = "verified.com"
      org = create(:organization)
      create(:verifiable_domain, owner: org, verified: true, domain: verified_domain)
      author = create(:user, email: "author@#{verified_domain}")
      org.add_member(author)
      committer = create(:user, email: "committer@#{verified_domain}")
      org.add_member(committer)

      info = @commit_info_with_co_authors.dup
      info["committer"] = [committer.login, committer.email, "2010-04-28T16:20:56Z"]
      info["author"] = [author.login, author.email, "2010-04-28T16:20:56Z"]
      info["trailers"] = { "on-behalf-of" => ["#{org.login} <example@not_verified.com>"] }
      commit = Commit.new @repo, info
      Platform::Loaders::GitSignature.expects(:load).with(commit).returns(@signed_signature)

      assert_nil commit.async_on_behalf_of.sync
    end

    test "commit message with author who is not a member of the org" do
      verified_domain = "verified.com"
      org = create(:organization)
      create(:verifiable_domain, owner: org, verified: true, domain: verified_domain)
      author = create(:user, email: "author@#{verified_domain}")
      committer = create(:user, email: "committer@#{verified_domain}")
      org.add_member(committer)

      info = @commit_info_with_co_authors.dup
      info["committer"] = [committer.login, committer.email, "2010-04-28T16:20:56Z"]
      info["author"] = [author.login, author.email, "2010-04-28T16:20:56Z"]
      info["trailers"] = { "on-behalf-of" => ["#{org.login} <org@#{verified_domain}>"] }
      commit = Commit.new @repo, info
      Platform::Loaders::GitSignature.expects(:load).with(commit).returns(@signed_signature)

      assert_nil commit.async_on_behalf_of.sync
    end

    test "commit message with commit that is not verified" do
      verified_domain = "verified.com"
      org = create(:organization)
      create(:verifiable_domain, owner: org, verified: true, domain: verified_domain)
      author = create(:user, email: "author@#{verified_domain}")
      org.add_member(author)
      committer = create(:user, email: "committer@#{verified_domain}")
      org.add_member(committer)

      info = @commit_info_with_co_authors.dup
      info["committer"] = [committer.login, committer.email, "2010-04-28T16:20:56Z"]
      info["author"] = [author.login, author.email, "2010-04-28T16:20:56Z"]
      info["trailers"] = { "on-behalf-of" => ["#{org.login} <org@#{verified_domain}>"] }
      commit = Commit.new @repo, info

      assert_nil commit.async_on_behalf_of.sync
    end

    test "strips @ from beginning of org login if provided" do
      verified_domain = "verified.com"
      org = create(:organization)
      create(:verifiable_domain, owner: org, verified: true, domain: verified_domain)
      author = create(:user, email: "author@#{verified_domain}")
      org.add_member(author)

      info = @commit_info_with_co_authors.dup
      info["committer"] = ["github", GitHub.web_committer_email, "2010-04-28T16:20:56Z"]
      info["author"] = [author.login, author.email, "2010-04-28T16:20:56Z"]
      info["trailers"] = { "on-behalf-of" => ["@#{org.login} <org@#{verified_domain}>"] }
      commit = Commit.new @repo, info
      Platform::Loaders::GitSignature.expects(:load).with(commit).returns(@signed_signature)

      assert_equal org, commit.async_on_behalf_of.sync
    end

    test "org name is not case sensitive" do
      verified_domain = "verified.com"
      org = create(:organization, login: "aggretsuko")
      create(:verifiable_domain, owner: org, verified: true, domain: verified_domain)
      author = create(:user, email: "author@#{verified_domain}")
      org.add_member(author)

      info = @commit_info_with_co_authors.dup
      info["committer"] = ["github", GitHub.web_committer_email, "2010-04-28T16:20:56Z"]
      info["author"] = [author.login, author.email, "2010-04-28T16:20:56Z"]
      info["trailers"] = { "on-behalf-of" => ["Aggretsuko <org@#{verified_domain}>"] }
      commit = Commit.new @repo, info
      Platform::Loaders::GitSignature.expects(:load).with(commit).returns(@signed_signature)

      assert_equal org, commit.async_on_behalf_of.sync
    end

    test "wrong syntax for trailer returns nil" do
      verified_domain = "verified.com"
      org = create(:organization)
      create(:verifiable_domain, owner: org, verified: true, domain: verified_domain)
      author = create(:user, email: "author@#{verified_domain}")
      org.add_member(author)
      committer = create(:user, email: "committer@#{verified_domain}")
      org.add_member(committer)

      info = @commit_info_with_co_authors.dup
      info["committer"] = [committer.login, committer.email, "2010-04-28T16:20:56Z"]
      info["author"] = [author.login, author.email, "2010-04-28T16:20:56Z"]
      info["trailers"] = { "on-behalf-of" => ["#{org.login} (org@#{verified_domain})"] }
      commit = Commit.new @repo, info
      Platform::Loaders::GitSignature.expects(:load).with(commit).returns(@signed_signature)

      assert_nil commit.async_on_behalf_of.sync
    end

    test "doesn't load/verify signature if there is no on-behalf-of trailer" do
      commit = Commit.new @repo, @commit_info
      Platform::Loaders::GitSignature.expects(:load).never

      assert_nil commit.async_on_behalf_of.sync
    end
  end

  context "#readable_by?" do
    test "returns true for a user with read access to the repo" do
      assert @commit.readable_by?(@committer)
    end

    test "returns false for a user who cannot read the repo" do
      private_repo = create :private_repository
      commit = Commit.new(private_repo, @commit_info)

      refute commit.readable_by?(@committer)
    end
  end
end

class EmuCommitTest < GitHub::TestCase
  include CommitSharedTests

  include GpgKeyHelper

  fixtures do
    @enterprise = create :business, :enterprise_managed, shortcode: "UPCASE"
    @owner          = create(:emu, :owner, business: @enterprise)

    @org            = create :organization, business: @enterprise, admin: @owner, plan: "bronze"

    @repo           = create(:repository, owner: @org)
    @simple         = create(:repository, owner: @owner)
    @messages       = create(:repository, owner: @org)

    @collab = create(:emu, business: @enterprise)
    @org.add_member(@collab, action: :write)
    @repo.add_member(@collab)
    @collab.watch_repo(@repo)

    @committer = create(:emu, business: @enterprise, email: "technoweenie@gmail.com", name: "technoweenie")
    @other_committer = create(:emu, business: @enterprise, email: "simon@rozet.name", name: "sr")

    @other_user = create(:emu, business: @enterprise, email: "mclark@github.com")
    @other_user.emails.create!(email: "watership+#{@enterprise.shortcode}@down.com")
    @github = create(:user, email: GitHub.web_committer_email)

    @commit_oid  = "3572d83ba062076f6a740379463d0f3f770d7fc5"
    @commit_info = {
      "oid"       => @commit_oid,
      "type"      => "commit",
      "message"   => "space change",
      "parents"   => ["c3956841a7cb7e8ba4a6fd923568d86958f01573"],
      "tree"      => "d9d67f971d948d0b43f1d91ead123e0b969556fe",
      "committer" => ["rick", "technoweenie@gmail.com", "2010-04-28T16:20:56Z"],
      "author"    => ["rick", "technoweenie@gmail.com", "2010-04-28T16:20:56Z"],
      "encoding"  => "UTF-8",
    }

    @commit_info_timestamp = {
      "oid"       => @commit_oid,
      "type"      => "commit",
      "message"   => "space change",
      "parents"   => ["c3956841a7cb7e8ba4a6fd923568d86958f01573"],
      "tree"      => "d9d67f971d948d0b43f1d91ead123e0b969556fe",
      "committer" => ["rick", "technoweenie@gmail.com", [1398662456, 39600]],
      "author"    => ["rick", "technoweenie@gmail.com", [1398662456, 39600]],
      "encoding"  => "UTF-8",
    }
    @commit_info_melbourne = {
      "oid"       => @commit_oid,
      "type"      => "commit",
      "message"   => "space change",
      "parents"   => ["c3956841a7cb7e8ba4a6fd923568d86958f01573"],
      "tree"      => "d9d67f971d948d0b43f1d91ead123e0b969556fe",
      "committer" => ["rick", "technoweenie@gmail.com", "2014-04-28T16:20:56+11:00"],
      "author"    => ["rick", "technoweenie@gmail.com", "2014-04-28T16:20:56+11:00"],
      "encoding"  => "UTF-8",
    }
    @commit_info_amsterdam = {
      "oid"       => @commit_oid,
      "type"      => "commit",
      "message"   => "space change",
      "parents"   => ["c3956841a7cb7e8ba4a6fd923568d86958f01573"],
      "tree"      => "d9d67f971d948d0b43f1d91ead123e0b969556fe",
      "committer" => ["rick", "technoweenie@gmail.com", "2014-04-28T16:20:56+01:00"],
      "author"    => ["rick", "technoweenie@gmail.com", "2014-04-28T16:20:56+01:00"],
      "encoding"  => "UTF-8",
    }
    @commit_info_pacific = {
      "oid"       => @commit_oid,
      "type"      => "commit",
      "message"   => "space change",
      "parents"   => ["c3956841a7cb7e8ba4a6fd923568d86958f01573"],
      "tree"      => "d9d67f971d948d0b43f1d91ead123e0b969556fe",
      "committer" => ["rick", "technoweenie@gmail.com", "2014-04-28T16:20:56-08:00"],
      "author"    => ["rick", "technoweenie@gmail.com", "2014-04-28T16:20:56-08:00"],
      "encoding"  => "UTF-8",
    }

    invalid_encoded_name = Marshal.load("\x04\bI\"\x19\xEC\x83\xA4\xEC\x9D\xB4\xEB\x8B?(\xEA\xB9\x80\xEC\xA7\x80\xED\x9B?)\x06:\rencoding\"\nCP949")

    @commit_info_bad_encoding = {
      "oid"       => @commit_oid,
      "type"      => "commit",
      "message"   => <<~MSG,
        space change

        co-authored-by: #{invalid_encoded_name} <mclark@github.com>
      MSG
      "parents"   => ["c3956841a7cb7e8ba4a6fd923568d86958f01573"],
      "tree"      => "d9d67f971d948d0b43f1d91ead123e0b969556fe",
      "committer" => [invalid_encoded_name, "nogood@gmail.com", "2010-04-28T16:20:56Z"],
      "author"    => [invalid_encoded_name, "nogood@gmail.com", "2010-04-28T16:20:56Z"],
      "encoding"  => "UTF-8",
      "trailers"  => {
        "co-authored-by" => ["#{invalid_encoded_name} <mclark@github.com>"],
      },
    }

    @commit_info_message_iso_8859_1_encoding = {
      "oid"       => @commit_oid,
      "type"      => "commit",
      "message"   => <<~MSG,
        Fu\xdfg\xe4nger\xfcberg\xe4nge
      MSG
      "parents"   => ["c3956841a7cb7e8ba4a6fd923568d86958f01573"],
      "tree"      => "d9d67f971d948d0b43f1d91ead123e0b969556fe",
      "committer" => [invalid_encoded_name, "nogood@gmail.com", "2010-04-28T16:20:56Z"],
      "author"    => [invalid_encoded_name, "nogood@gmail.com", "2010-04-28T16:20:56Z"],
      "encoding"  => "ISO-8859-1",
      "trailers"  => {
        "co-authored-by" => ["#{invalid_encoded_name} <mclark@github.com>"],
      },
    }

    @commit_info_mentions_commit_without_pre_expanded_shas = {
      "oid"       => @commit_oid,
      "type"      => "commit",
      "message"   => "space change c395684 abcd1234",
      "parents"   => ["c3956841a7cb7e8ba4a6fd923568d86958f01573"],
      "tree"      => "d9d67f971d948d0b43f1d91ead123e0b969556fe",
      "committer" => ["rick", "technoweenie@gmail.com", "2010-04-28T16:20:56Z"],
      "author"    => ["rick", "technoweenie@gmail.com", "2010-04-28T16:20:56Z"],
      "encoding"  => "UTF-8",
    }

    @commit_info_mentions_commit_with_pre_expanded_shas = {
      "oid"       => @commit_oid,
      "type"      => "commit",
      "message"   => "space change c395684 abcd1234",
      "message_shas" => { "abcd1234" => "abcd1234abcd1234abcd1234abcd1234abcd1234" },
      "parents"   => ["c3956841a7cb7e8ba4a6fd923568d86958f01573"],
      "tree"      => "d9d67f971d948d0b43f1d91ead123e0b969556fe",
      "committer" => ["rick", "technoweenie@gmail.com", "2010-04-28T16:20:56Z"],
      "author"    => ["rick", "technoweenie@gmail.com", "2010-04-28T16:20:56Z"],
      "encoding"  => "UTF-8",
    }

    @commit_info_with_co_authors = {
      "oid"       => @commit_oid,
      "type"      => "commit",
      "message"   => <<~MSG,
        our sweet 🍐ing change

        co-authored-by: Matt Clark <mclark@github.com>
      MSG
      "message_shas" => { "abcd1234" => "abcd1234abcd1234abcd1234abcd1234abcd1234" },
      "parents"   => ["c3956841a7cb7e8ba4a6fd923568d86958f01573"],
      "tree"      => "d9d67f971d948d0b43f1d91ead123e0b969556fe",
      "committer" => ["Matt Clark", "mclark@github.com", "2010-04-28T16:20:56Z"],
      "author"    => ["rick", "technoweenie@gmail.com", "2010-04-28T16:20:56Z"],
      "encoding"  => "UTF-8",
      "trailers"  => {
        "co-authored-by" => 2.times.map { "Matt Clark <mclark@github.com>" },
      },
    }

    @commit_info_with_dup_user = @commit_info_with_co_authors.dup
    @commit_info_with_dup_user["trailers"] = {
      "co-authored-by" => @commit_info_with_dup_user["trailers"]["co-authored-by"].dup << "Matthew <watership@down.com>",
    }

    @signed = create(:repository, owner: @org)
    @signing_key = create_gpg_key business: @enterprise, emu: true
    @user = @signing_key.user
    @other_signing_key = create_gpg_key("two")

    @smime_email = @signing_key.emails.first.email
    user_login = @user.login.split("_#{@enterprise.shortcode}").join

    smime_ca = FakeCA.new("/CN=root1")
    @smime_cert = smime_ca.issue("/CN=#{user_login}/emailAddress=#{@smime_email}").freeze
    GitHub.git_signing_smime_cert_store.add_cert(smime_ca.parsed)
  end

  setup do
    example_repo :commit_test, @repo
    example_repo :simple, @simple
    example_repo :messages, @messages
    example_repo :signed_commits, @signed

    @smime_commit_oid = @smime_cert.create_signed_commit(@signed, @user)
    @smime_commit = @signed.commits.find(@smime_commit_oid)
    @signed_signature = Platform::Loaders::GitSignature.load(@smime_commit)

    reset_cache

    @commit = Commit.new(@repo, @commit_info)
    @commit_timestamp = Commit.new(@repo, @commit_info_timestamp)
    @commit_melbourne = Commit.new(@repo, @commit_info_melbourne)
    @commit_amsterdam = Commit.new(@repo, @commit_info_amsterdam)
    @commit_pacific = Commit.new(@repo, @commit_info_pacific)
  end

  test "async authors contains just the author when on user repo" do
    commit = Commit.new(@simple, @commit_info)

    assert_equal [commit.author], commit.async_authors.sync
  end
end unless GitHub.single_business_environment?

class MentionedTeamsTest < GitHub::TestCase
  fixtures do
    @committer = create(:user)
    @org = create(:organization, login: "jdoe-org", admin: @committer, plan: "bronze")
    @team = create(:team, name: "super-friends-team", organization: @org, permission: "pull")
    @repo = create(:repository)
    @team.add_repository @repo, :pull
    @team_repo = create(:repository, owner: @org)
    @team.add_member @committer
  end

  test "#mentioned_teams" do
    commit_info = { message: "Hey @#{@org.login}/#{@team.name}", committer: @committer }
    commit = @team_repo.heads.find_or_build("master").append_commit(commit_info, @committer) do |files|
      files.add("README", "cool project")
    end

    assert_equal [@team], commit.mentioned_teams
  end
end

module CommitGpgSignatureVerificationSharedTests
  extend T::Helpers

  requires_ancestor { GitHub::TestCase }

  def test_has_signature_can_detect_if_commit_is_signed
    assert_predicate @gpg_commit, :has_signature?
    assert_predicate @smime_commit, :has_signature?
    refute_predicate @unsigned_commit, :has_signature?
  end

  def test_has_signature_does_not_raise_for_corrupt_commits
    assert_predicate @corrupt_gpg_commit, :has_signature?
  end

  def test_gpg_signature_true_if_gpg_signed
    assert_predicate @gpg_commit, :gpg_signature?
  end

  def test_gpg_signature_false_if_unsigned
    refute_predicate @unsigned_commit, :gpg_signature?
  end

  def test_gpg_signature_false_if_not_gpg_signed
    refute_predicate @smime_commit, :gpg_signature?
  end

  def test_smime_signature_true_if_smime_signed
    assert_predicate @smime_commit, :smime_signature?
  end

  def test_smime_signature_false_if_unsigned
    refute_predicate @unsigned_commit, :smime_signature?
  end

  def test_smime_signature_false_if_not_smime_signed
    refute_predicate @gpg_commit, :smime_signature?
  end

  def test_signer_is_loaded_from_the_committer_email_address
    assert_equal @user, @gpg_commit.signer
    assert_equal @user, @smime_commit.signer
    assert_equal @user, @wrong_key_gpg_commit.signer
  end

  def test_signature_issuer_key_id_gets_key_id_from_signature
    assert_equal @signing_key.key_id, @gpg_commit.signature_issuer_key_id
    assert_nil @unsigned_commit.signature_issuer_key_id
  end

  def test_signature_issuer_key_id_gets_key_id_from_signature_in_hex
    assert_equal @signing_key.hex_key_id, @gpg_commit.signature_issuer_key_id_hex
  end

  def test_signature_issuer_key_id_is_nil_if_gpg_backend_is_unavailable
    GitHub.gpg.instance_variable_set(:@available, false)
    GitHub.gpg.expects(:signature_issuer_key_ids).never

    assert_nil @unsigned_commit.signature_issuer_key_id
  end

  def test_signature_issuer_key_id_returns_nil_for_gpgverify_errors
    GitHub.gpg.stubs(:signature_issuer_key_ids).raises(GpgVerify::Unavailable)

    assert_nil @unsigned_commit.signature_issuer_key_id
  end

  def test_signature_issuer_key_id_does_not_raise_for_corrupt_commits
    assert_nil @corrupt_gpg_commit.signature_issuer_key_id
  end

  def test_signature_issuer_key_id_nil_for_smime_signatures
    assert_nil @smime_commit.signature_issuer_key_id
  end

  def test_verified_signature_checks_that_signature_is_present_and_valid
    assert_predicate @gpg_commit, :verified_signature?, "GPG should be verified"
    refute_predicate @gpg_commit, :unverified_signature?

    assert_predicate @smime_commit, :verified_signature?, "smime should be verified"
    refute_predicate @smime_commit, :unverified_signature?

    refute_predicate @wrong_key_gpg_commit, :verified_signature?
    assert_predicate @wrong_key_gpg_commit, :unverified_signature?

    refute_predicate @unsigned_commit, :verified_signature?
    refute_predicate @unsigned_commit, :unverified_signature?

    refute_predicate @corrupt_gpg_commit, :verified_signature?
    assert_predicate @corrupt_gpg_commit, :unverified_signature?
  end

  def test_verified_signature_checks_that_committer_email_matches_key_email
    user = @signing_key.user
    user.email_roles.delete_all
    user.emails.where(email: user.emails.first.email).delete_all
    refute_predicate @gpg_commit, :verified_signature?
  end

  def test_verified_signature_checks_that_committer_email
    @signing_key.user.emails.each(&:unverify!)

    if @user.is_enterprise_managed?
      assert_predicate @gpg_commit, :verified_signature?
    elsif GitHub.email_verification_enabled?
      refute_predicate @gpg_commit, :verified_signature?
    else
      assert_predicate @gpg_commit, :verified_signature?
    end
  end

  def test_commit_prefill_verified_signature_prefills_signature_for_multiple_commits
    Commit.prefill_verified_signature([
        @gpg_commit,
        @smime_commit,
        @unsigned_commit,
        @wrong_key_gpg_commit,
      ], @signed)

    GitRPC::Client.any_instance.expects(:parse_commit_signatures).never
    GitHub.gpg.expects(:signature_issuer_key_ids).never

    assert_equal @signing_key.key_id, @gpg_commit.signature_issuer_key_id
    assert_nil @smime_commit.signature_issuer_key_id
    assert_nil @unsigned_commit.signature_issuer_key_id
    assert_equal "s\x00y\b\xA1\x92\xE5 ".b, @wrong_key_gpg_commit.signature_issuer_key_id
  end

  def test_commit_prefill_verified_signature_prefills_verified_signature_for_multiple_commits
    Commit.prefill_verified_signature([
        @gpg_commit,
        @smime_commit,
        @unsigned_commit,
        @wrong_key_gpg_commit,
      ], @signed)

    GitHub.gpg.expects(:batch_verify).never

    assert_predicate @gpg_commit, :verified_signature?
    assert_predicate @smime_commit, :verified_signature?
    refute_predicate @unsigned_commit, :verified_signature?
    refute_predicate @wrong_key_gpg_commit, :verified_signature?
  end

  # if a signature is somehow blank, it's invalid. don't throw an error.
  def test_commit_prefill_verified_signature_handles_blank_signatures
    @signed.rpc.stubs(:parse_commit_signatures).returns([["", ""]])

    Commit.prefill_verified_signature([
        @gpg_commit,
      ], @signed)

    refute_predicate @gpg_commit, :verified_signature?
  end

  def test_commit_prefill_signing_data_rescues_from_missing_oid
    @gpg_commit.oid = SecureRandom.hex(20)
    Commit.prefill_signing_data([@gpg_commit])

    Commit.expects(:parse_signing_data).never

    assert_nil @gpg_commit.signature
    assert_nil @gpg_commit.signing_payload
  end
end

class CommitGpgSignatureVerificationTest < GitHub::TestCase
  include CommitGpgSignatureVerificationSharedTests

  include GpgKeyHelper

  fixtures do
    @signed = create(:repository)
    @signing_key = create_gpg_key
    @user = @signing_key.user
    create(:user_email, :verified, user: @user, email: "mastahyeti@github.com")
    @other_signing_key = create_gpg_key("two")

    @gpg_commit_oid = "378718a43decc3471c6a90b8aac95440a4e11152"
    @unsigned_commit_oid = "d014786a170b6ef6ed6a1814be8c941db39cd259"
    @wrong_key_gpg_commit_oid = "a1b6decaaac768b5e01e1b5dbf5b2cc081bed1eb"
    @corrupt_gpg_commit_oid = "cb842b3b6e8dc7fdef91b4bc564862fd8af271ea"

    smime_ca = FakeCA.new("/CN=root1")
    @smime_cert = smime_ca.issue("/CN=#{@user.login}/emailAddress=#{@user.emails.verified.first.email}").freeze
    GitHub.git_signing_smime_cert_store.add_cert(smime_ca.parsed)
  end

  setup do
    example_repo :signed_commits, @signed
    @gpg_commit = @signed.commits.find(@gpg_commit_oid)
    @unsigned_commit = @signed.commits.find(@unsigned_commit_oid)
    @wrong_key_gpg_commit = @signed.commits.find(@wrong_key_gpg_commit_oid)
    @corrupt_gpg_commit = @signed.commits.find(@corrupt_gpg_commit_oid)

    @smime_commit_oid = @smime_cert.create_signed_commit(@signed, @user)
    @smime_commit = @signed.commits.find(@smime_commit_oid)
  end
end

class EmuCommitGpgSignatureVerificationTest < GitHub::TestCase
  include CommitGpgSignatureVerificationSharedTests

  include GpgKeyHelper

  fixtures do
    @signing_key = create_gpg_key emu: true
    @user = @signing_key.user
    create(:user_email, :verified, user: @user, email: "mastahyeti@github.com")
    @signed = create(:repository, owner: @user)

    @enterprise = @user.enterprise_managed_business

    @other_signing_key = create_gpg_key "two", business: @enterprise, emu: true

    @gpg_commit_oid = "378718a43decc3471c6a90b8aac95440a4e11152"
    @unsigned_commit_oid = "d014786a170b6ef6ed6a1814be8c941db39cd259"
    @wrong_key_gpg_commit_oid = "a1b6decaaac768b5e01e1b5dbf5b2cc081bed1eb"
    @corrupt_gpg_commit_oid = "cb842b3b6e8dc7fdef91b4bc564862fd8af271ea"

    @smime_email = @signing_key.emails.first.email
    user_login = @user.login.split("_#{@enterprise.shortcode}").join

    smime_ca = FakeCA.new("/CN=root1")
    @smime_cert = smime_ca.issue("/CN=#{user_login}/emailAddress=#{@smime_email}").freeze
    GitHub.git_signing_smime_cert_store.add_cert(smime_ca.parsed)
  end

  setup do
    example_repo :signed_commits, @signed
    @gpg_commit = @signed.commits.find(@gpg_commit_oid)
    @unsigned_commit = @signed.commits.find(@unsigned_commit_oid)
    @wrong_key_gpg_commit = @signed.commits.find(@wrong_key_gpg_commit_oid)
    @corrupt_gpg_commit = @signed.commits.find(@corrupt_gpg_commit_oid)

    @smime_commit_oid = @smime_cert.create_signed_commit(@signed, @user)
    @smime_commit = @signed.commits.find(@smime_commit_oid)
  end
end unless GitHub.single_business_environment?

class CommitDeterminingWhichPrIntroducedItTest < GitHub::TestCase
  fixtures do
    create_search_indices

    @repo = create(:repository, from_example: :simple)
    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  def refresh
    @index ||= Elastomer::Indexes::PullRequests.new
    @index.refresh
  end

  def make_commit(parent_oid: nil, branch_name: "test_branch", repo: @repo)
    line = T.must(caller[1])
    num  = T.must(line.match(/:(\d+):in [`']/))[1]
    metadata = { message: "test commit (from line #{num})", committer: repo.owner }

    parent_oid ||= repo.heads.find("master").target_oid
    commit       = repo.commits.create(metadata, parent_oid) {}

    repo.heads.create(branch_name, commit.oid, repo.owner)

    commit
  end

  def make_pull(head_branch: "test_branch", base_branch: "master", repo: @repo)
    GitHub::RateLimitedCreation.disable_content_creation_rate_limits do
      PullRequest.create_for(repo,
        user: repo.owner,
        base: base_branch,
        head: head_branch,
        title: "test PR",
        body: "just a test",
      )
    end
  end

  def make_commit_and_pull(parent_oid: nil, branch_name: "test_branch", base_branch: "master", repo: @repo)
    commit = make_commit(parent_oid: parent_oid, branch_name: branch_name, repo: repo)
    pull   = make_pull(head_branch: branch_name, repo: repo)

    [commit, pull]
  end

  def make_fork
    return if defined?(@fork)
    @fork = create(:fork_repository, forker: create(:user), fork_repo: @repo, from_example: :simple)
  end

  def sync_commit(commit, from:, to:)
    to.rpc.fetch_commits(from.shard_path, commit.oid)
    to.commits.find(commit.oid)
  end

  def make_fork_with_commit(commit)
    make_fork
    sync_commit(commit, from: @repo, to: @fork)
  end

  context "#introductory_pull_request" do
    test "returns nil when the commit is not part of a PR" do
      commit = make_commit

      assert_nil commit.introductory_pull_request(viewer: @owner)
    end

    test "returns nil when the commit is part of an unmerged PR" do
      commit, pull = make_commit_and_pull

      perform_enqueued_jobs(only: [AddToSearchIndexJob]) do
        pull.synchronize_search_index
      end
      refresh

      assert_nil commit.introductory_pull_request(viewer: @owner)
    end

    test "returns nil when the commit is part of multiple unmerged PRs" do
      commit, pull_one     = make_commit_and_pull
      commit_two, pull_two = make_commit_and_pull(parent_oid: commit.oid, branch_name: "test_branch_two")

      perform_enqueued_jobs(only: [AddToSearchIndexJob]) do
        pull_one.synchronize_search_index
        pull_two.synchronize_search_index
      end
      refresh

      assert_nil commit.introductory_pull_request(viewer: @owner)
    end

    test "returns the PR that merged the commit in" do
      commit, pull = make_commit_and_pull

      perform_enqueued_jobs(only: [AddToSearchIndexJob]) do
        pull.merge
        pull.synchronize_search_index
      end
      refresh

      assert_equal pull, commit.introductory_pull_request(viewer: @owner)
    end

    test "returns nil when the pull was made on a fork" do
      make_fork
      commit, fork_pull = make_commit_and_pull(repo: @fork)

      fork_pull.merge

      perform_enqueued_jobs(only: [AddToSearchIndexJob]) do
        fork_pull.synchronize_search_index
      end
      refresh

      sync_commit(commit, from: @fork, to: @repo)

      parent_commit = @repo.commits.find(commit.oid)
      refute_nil parent_commit

      assert_nil parent_commit.introductory_pull_request(viewer: @repo.owner)
    end

    test "returns nil for a fork when the pull was made on the base" do
      make_fork
      commit, pull = make_commit_and_pull

      pull.merge

      perform_enqueued_jobs(only: [AddToSearchIndexJob]) do
        pull.synchronize_search_index
      end
      refresh

      sync_commit(commit, from: @repo, to: @fork)

      fork_commit = @fork.commits.find(commit.oid)
      refute_nil fork_commit

      assert_nil fork_commit.introductory_pull_request(viewer: @fork.owner)
    end

    test "returns the PR that merged the commit in even when the commit is part of multiple PRs" do
      commit, pull_one     = make_commit_and_pull
      commit_two, pull_two = make_commit_and_pull(parent_oid: commit.oid, branch_name: "test_branch_two")

      pull_one.merge

      perform_enqueued_jobs(only: [AddToSearchIndexJob]) do
        pull_one.synchronize_search_index
        pull_two.synchronize_search_index
      end
      refresh

      assert_equal pull_one, commit.introductory_pull_request(viewer: @owner)
    end

    test "returns the PR that merged the commit in even when the commit is part of multiple PRs and the second was merged" do
      commit, pull_one     = make_commit_and_pull
      commit_two, pull_two = make_commit_and_pull(parent_oid: commit.oid, branch_name: "test_branch_two")

      pull_two.merge

      perform_enqueued_jobs(only: [AddToSearchIndexJob]) do
        pull_one.synchronize_search_index
        pull_two.synchronize_search_index
      end
      refresh

      assert_equal pull_two, commit.introductory_pull_request(viewer: @owner)
    end

    test "returns the PR that merged the commit in even when the commit is part of multiple PRs and both were merged" do
      commit, pull_one     = make_commit_and_pull
      commit_two, pull_two = make_commit_and_pull(parent_oid: commit.oid, branch_name: "test_branch_two")

      pull_one.merge
      pull_two.merge

      perform_enqueued_jobs(only: [AddToSearchIndexJob]) do
        pull_one.synchronize_search_index
        pull_two.synchronize_search_index
      end
      refresh

      assert_equal pull_one, commit.introductory_pull_request(viewer: @owner)
    end

    test "returns the PR that merged the commit in even when the commit is part of multiple PRs and both were merged, second one first" do
      commit, pull_one     = make_commit_and_pull
      commit_two, pull_two = make_commit_and_pull(parent_oid: commit.oid, branch_name: "test_branch_two")

      pull_two.merge
      pull_one.merge

      perform_enqueued_jobs(only: [AddToSearchIndexJob]) do
        pull_one.synchronize_search_index
        pull_two.synchronize_search_index
      end
      refresh

      assert_equal pull_two, commit.introductory_pull_request(viewer: @owner)
    end

    test "returns the PR that merged the commit in even with stacked PRs" do
      commit, pull_one     = make_commit_and_pull
      commit_two, pull_two = make_commit_and_pull(parent_oid: commit.oid, branch_name: "test_branch_two", base_branch: pull_one.head_ref_name)

      pull_two.merge
      pull_one.merge

      perform_enqueued_jobs(only: [AddToSearchIndexJob]) do
        pull_one.synchronize_search_index
        pull_two.synchronize_search_index
      end
      refresh

      assert_equal pull_two, commit_two.introductory_pull_request(viewer: @owner)
    end

    test "returns nil when the merged PR has been removed" do
      commit, pull = make_commit_and_pull

      perform_enqueued_jobs(only: [AddToSearchIndexJob]) do
        pull.merge
        pull.synchronize_search_index
      end
      refresh

      assert_equal pull, commit.introductory_pull_request(viewer: @owner)

      pull.destroy
      assert_nil PullRequest.find_by(id: pull.id)

      assert_nil commit.introductory_pull_request(viewer: @owner)
    end

    if GitHub.spamminess_check_enabled?
      test "doesn't return PR on spammy repo for non-staff viewer" do
        commit, pull = make_commit_and_pull

        pull.merge

        perform_enqueued_jobs(only: [AddToSearchIndexJob]) do
          pull.synchronize_search_index
        end
        refresh
        pull.repository.update_column(:user_hidden, true)

        assert_nil commit.introductory_pull_request(viewer: @owner)
      end

      test "doesn't return spammy PR for non-staff viewer" do
        commit, pull = make_commit_and_pull

        pull.merge

        perform_enqueued_jobs(only: [AddToSearchIndexJob]) do
          pull.synchronize_search_index
        end
        refresh
        pull.update_column(:user_hidden, true)

        assert_nil commit.introductory_pull_request(viewer: @owner)
      end

      test "returns spammy PR for staff viewer" do
        commit, pull = make_commit_and_pull

        pull.merge

        perform_enqueued_jobs(only: [AddToSearchIndexJob]) do
          pull.synchronize_search_index
        end
        refresh
        pull.repository.update_column(:user_hidden, true)

        assert_equal pull, commit.introductory_pull_request(viewer: create(:staff_admin_user))
      end
    end
  end

  context "#parent_introductory_pull_request" do
    test "returns nil when the commit is not part of a PR" do
      commit = make_commit
      fork_commit = make_fork_with_commit(commit)

      assert_nil fork_commit.parent_introductory_pull_request(viewer: @fork.owner)
    end

    test "returns nil when the commit is part of an unmerged PR" do
      commit, pull = make_commit_and_pull

      perform_enqueued_jobs(only: [AddToSearchIndexJob]) do
        pull.synchronize_search_index
      end
      refresh

      fork_commit = make_fork_with_commit(commit)

      assert_nil fork_commit.parent_introductory_pull_request(viewer: @fork.owner)
    end

    test "returns nil when the commit is part of multiple unmerged PRs" do
      commit, pull_one     = make_commit_and_pull
      commit_two, pull_two = make_commit_and_pull(parent_oid: commit.oid, branch_name: "test_branch_two")

      perform_enqueued_jobs(only: [AddToSearchIndexJob]) do
        pull_one.synchronize_search_index
        pull_two.synchronize_search_index
      end
      refresh

      fork_commit = make_fork_with_commit(commit)

      assert_nil fork_commit.parent_introductory_pull_request(viewer: @fork.owner)
    end

    test "returns the PR that merged the commit in" do
      commit, pull = make_commit_and_pull

      pull.merge

      perform_enqueued_jobs(only: [AddToSearchIndexJob]) do
        pull.synchronize_search_index
      end
      refresh

      fork_commit = make_fork_with_commit(commit)

      assert_equal pull, fork_commit.parent_introductory_pull_request(viewer: @fork.owner)
    end

    test "returns nil when the pull was made on a fork" do
      make_fork
      commit, fork_pull = make_commit_and_pull(repo: @fork)

      fork_pull.merge

      perform_enqueued_jobs(only: [AddToSearchIndexJob]) do
        fork_pull.synchronize_search_index
      end
      refresh

      assert_nil commit.parent_introductory_pull_request(viewer: @repo.owner)
    end

    test "returns the PR that merged the commit in even when the commit is part of multiple PRs" do
      commit, pull_one     = make_commit_and_pull
      commit_two, pull_two = make_commit_and_pull(parent_oid: commit.oid, branch_name: "test_branch_two")

      pull_one.merge

      perform_enqueued_jobs(only: [AddToSearchIndexJob]) do
        pull_one.synchronize_search_index
        pull_two.synchronize_search_index
      end
      refresh

      fork_commit = make_fork_with_commit(commit)

      assert_equal pull_one, fork_commit.parent_introductory_pull_request(viewer: @fork.owner)
    end

    test "returns the PR that merged the commit in even when the commit is part of multiple PRs and the second was merged" do
      commit, pull_one     = make_commit_and_pull
      commit_two, pull_two = make_commit_and_pull(parent_oid: commit.oid, branch_name: "test_branch_two")

      pull_two.merge

      perform_enqueued_jobs(only: [AddToSearchIndexJob]) do
        pull_one.synchronize_search_index
        pull_two.synchronize_search_index
      end
      refresh

      fork_commit = make_fork_with_commit(commit)

      assert_equal pull_two, fork_commit.parent_introductory_pull_request(viewer: @fork.owner)
    end

    test "returns the PR that merged the commit in even when the commit is part of multiple PRs and both were merged" do
      commit, pull_one     = make_commit_and_pull
      commit_two, pull_two = make_commit_and_pull(parent_oid: commit.oid, branch_name: "test_branch_two")

      pull_one.merge
      pull_two.merge

      perform_enqueued_jobs(only: [AddToSearchIndexJob]) do
        pull_one.synchronize_search_index
        pull_two.synchronize_search_index
      end
      refresh

      fork_commit = make_fork_with_commit(commit)

      assert_equal pull_one, fork_commit.parent_introductory_pull_request(viewer: @fork.owner)
    end

    test "returns the PR that merged the commit in even when the commit is part of multiple PRs and both were merged, second one first" do
      commit, pull_one     = make_commit_and_pull
      commit_two, pull_two = make_commit_and_pull(parent_oid: commit.oid, branch_name: "test_branch_two")

      pull_two.merge
      pull_one.merge

      perform_enqueued_jobs(only: [AddToSearchIndexJob]) do
        pull_one.synchronize_search_index
        pull_two.synchronize_search_index
      end
      refresh

      fork_commit = make_fork_with_commit(commit)

      assert_equal pull_two, fork_commit.parent_introductory_pull_request(viewer: @fork.owner)
    end

    test "returns the PR that merged the commit in even with stacked PRs" do
      commit, pull_one     = make_commit_and_pull
      commit_two, pull_two = make_commit_and_pull(parent_oid: commit.oid, branch_name: "test_branch_two", base_branch: pull_one.head_ref_name)

      pull_two.merge
      pull_one.merge

      perform_enqueued_jobs(only: [AddToSearchIndexJob]) do
        pull_one.synchronize_search_index
        pull_two.synchronize_search_index
      end
      refresh

      fork_commit = make_fork_with_commit(commit)

      assert_equal pull_two, fork_commit.parent_introductory_pull_request(viewer: @fork.owner)
    end

    test "returns nil when the merged PR has been removed" do
      commit, pull = make_commit_and_pull

      pull.merge

      perform_enqueued_jobs(only: [AddToSearchIndexJob]) do
        pull.synchronize_search_index
      end
      refresh

      fork_commit = make_fork_with_commit(commit)

      assert_equal pull, fork_commit.parent_introductory_pull_request(viewer: @fork.owner)

      pull.destroy
      assert_nil PullRequest.find_by(id: pull.id)

      assert_nil fork_commit.parent_introductory_pull_request(viewer: @fork.owner)
    end

    test "raises exception when finding the merged PR causes a search error" do
      commit, pull = make_commit_and_pull

      pull.merge

      perform_enqueued_jobs(only: [AddToSearchIndexJob]) do
        pull.synchronize_search_index
      end
      refresh

      fork_commit = make_fork_with_commit(commit)

      assert_equal pull, fork_commit.parent_introductory_pull_request(viewer: @fork.owner)

      @index.class.any_instance.stubs(:search).raises(ElastomerClient::Client::Error.new("problem"))

      # Re-fetch the commit as the result from the above call is memoized.
      fork_commit = fork_commit.repository.commits.find(commit.oid)

      assert_raises Commit::AssociatedPullRequestSearchFailed do
        fork_commit.parent_introductory_pull_request(viewer: @fork.owner)
      end
    end

    test "doesn't return PR on disabled repo for non-staff viewer" do
      commit, pull = make_commit_and_pull

      pull.merge

      perform_enqueued_jobs(only: [AddToSearchIndexJob]) do
        pull.synchronize_search_index
      end
      refresh
      pull.repository.access.disable("size", create(:user, :staff))

      fork_commit = make_fork_with_commit(commit)

      assert_nil fork_commit.parent_introductory_pull_request(viewer: @fork.owner)
    end

    if GitHub.spamminess_check_enabled?
      test "doesn't return PR on spammy repo for non-staff viewer" do
        commit, pull = make_commit_and_pull

        pull.merge

        perform_enqueued_jobs(only: [AddToSearchIndexJob]) do
          pull.synchronize_search_index
        end
        refresh
        pull.repository.update_column(:user_hidden, true)

        fork_commit = make_fork_with_commit(commit)

        assert_nil fork_commit.parent_introductory_pull_request(viewer: @fork.owner)
      end

      test "doesn't return spammy PR for non-staff viewer" do
        commit, pull = make_commit_and_pull

        pull.merge

        perform_enqueued_jobs(only: [AddToSearchIndexJob]) do
          pull.synchronize_search_index
        end
        refresh
        pull.update_column(:user_hidden, true)

        fork_commit = make_fork_with_commit(commit)

        assert_nil fork_commit.parent_introductory_pull_request(viewer: @fork.owner)
      end

      test "returns spammy PR for staff viewer" do
        commit, pull = make_commit_and_pull

        pull.merge

        perform_enqueued_jobs(only: [AddToSearchIndexJob]) do
          pull.synchronize_search_index
        end
        refresh
        pull.repository.update_column(:user_hidden, true)

        fork_commit = make_fork_with_commit(commit)

        assert_equal pull, fork_commit.parent_introductory_pull_request(viewer: create(:staff_admin_user))
      end
    end
  end

  test "prefill_combined_statuses attaches combined statuses to a list of commits without loading them individually" do
    # experiments here can mess up the query count, so turn science off:
    GitHub::Experiment.any_instance.stubs(:enabled?).returns(false)

    (sha, sha2) = @repo.heads.to_a.map(&:sha).uniq.slice(0, 2)

    create :status, repository: @repo, state: "pending", sha: sha,  context: "context1"
    status1 = create :status, repository: @repo, state: "failure", sha: sha,  context: "context1"
    status2 = create :status, repository: @repo, state: "success", sha: sha, context: "context2"
    create :status, repository: @repo, state: "pending", sha: sha2,  context: "context1"
    status3 = create :status, repository: @repo, state: "failure", sha: sha2,  context: "context1"
    status4 = create :status, repository: @repo, state: "success", sha: sha2, context: "context2"

    commit1 = commit2 = T.let(nil, T.untyped)
    assert_query_count 0 do
      commit1 = @repo.commits.find(sha)
      commit2 = @repo.commits.find(sha2)
    end

    assert_queries_matching /SELECT `statuses`\.\* FROM `statuses`/, 1 do
      Commit.prefill_combined_statuses([commit1, commit2], @repo)
    end

    assert_queries_matching /SELECT `statuses`\.\* FROM `statuses`/, 0 do
      assert_same_elements [status1, status2], commit1.combined_status.statuses
      assert_same_elements [status3, status4], commit2.combined_status.statuses
    end
  end
end

class RepositoriesTest < GitHub::TestCase
  fixtures do
    @owner       = create(:user)
    @repo        = create(:repository, owner: @owner)
    @commit_oid  = "3572d83ba062076f6a740379463d0f3f770d7fc5"
    @commit_info = {
      "oid"       => @commit_oid,
      "type"      => "commit",
      "message"   => "space change",
      "parents"   => ["c3956841a7cb7e8ba4a6fd923568d86958f01573"],
      "tree"      => "d9d67f971d948d0b43f1d91ead123e0b969556fe",
      "committer" => ["rick", "technoweenie@gmail.com", "2010-04-28T16:20:56Z"],
      "author"    => ["rick", "technoweenie@gmail.com", "2010-04-28T16:20:56Z"],
      "encoding"  => "UTF-8",
    }
  end

  test "#repositories returns Set with #repository" do
    commit = Commit.new(@repo, @commit_info)

    assert_equal @repo, commit.repository
    assert_equal @repo, commit.repositories.first
  end

  test "#repositories= assigns new repositories to Set" do
    commit = Commit.new(@repo, @commit_info)
    repo1 = create(:repository, owner: @owner)
    repo2 = create(:repository, owner: @owner)

    assert_equal @repo, commit.repository

    commit.repositories = [repo1, repo2]

    assert_includes commit.repositories, repo1
    assert_includes commit.repositories, repo2
    refute_includes commit.repositories, @repo
  end

  test "cannot add a non-repo to the repositories set" do
    commit = Commit.new(@repo, @commit_info)
    assert_raises TypeError do
      commit.repositories = [create(:user)]
    end
  end

  test "can assign a singular repo via the repositories= method" do
    commit = Commit.new(@repo, @commit_info)
    repo1 = create(:repository, owner: @owner)

    assert_equal @repo, commit.repository

    commit.repositories = repo1

    assert_includes commit.repositories, repo1
    refute_includes commit.repositories, @repo
  end

  context "#og_image_url" do
    test "it returns enhanced opengraph image url with correct cache key" do
      commit = Commit.new(@repo, @commit_info)

      # calculate expected cache key from specific resource attributes
      cache_key = Digest::SHA256.hexdigest(
        [
          commit.oid,
          @repo.name,
          @repo.owner_id,
        ].join(":")
      )

      # enhanced opengraph url with expected cache slug
      image_url = "#{GitHub.og_image_generator_base_url}/#{cache_key}#{commit.permalink(include_host: false)}"

      assert_equal image_url, commit.og_image_url
    end
  end

  context "#peel_to_commit" do
    test "it returns itself" do
      commit = Commit.new(@repo, @commit_info)
      assert_equal(commit, commit.peel_to_commit)
    end
  end
end
