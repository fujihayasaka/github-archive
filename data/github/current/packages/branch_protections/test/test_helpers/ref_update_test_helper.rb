# typed: strict
# frozen_string_literal: true

module RulesEngine
  module RefUpdateTestHelper

    sig { returns(String) }
    def create_random_sha
      SecureRandom.hex(20)
    end

    sig { params(repository: Repository, name: String, before_oid: String, after_oid: String, fast_forward: T.nilable(T::Boolean)).returns(Git::Ref::Update) }
    def create_branch_update(repository, name: "main", before_oid: GitHub::NULL_OID, after_oid: create_random_sha, fast_forward: nil)
      create_ref_update(repository, name: "refs/heads/#{name}", before_oid: before_oid, after_oid: after_oid, fast_forward: fast_forward)
    end

    sig { params(repository: Repository, name: String, before_oid: String, after_oid: String, fast_forward: T.nilable(T::Boolean)).returns(Git::Ref::Update) }
    def create_tag_update(repository, name: "v1.0", before_oid: GitHub::NULL_OID, after_oid: create_random_sha, fast_forward: nil)
      create_ref_update(repository, name: "refs/tags/#{name}", before_oid: before_oid, after_oid: after_oid, fast_forward: fast_forward)
    end

    sig { params(repository: Repository, name: String, before_oid: String, after_oid: String, fast_forward: T.nilable(T::Boolean)).returns(Git::Ref::Update) }
    def create_ref_update(repository, name: "refs/heads/main", before_oid: GitHub::NULL_OID, after_oid: create_random_sha, fast_forward: nil)
      Git::Ref::Update.new(repository: repository, refname: name, before_oid: before_oid, after_oid: after_oid, fast_forward: fast_forward)
    end

    sig { params(repo: Repository, actor: T.untyped).returns(T::Array[T.untyped]) }
    def simple_ref_update_setup(repo, actor)
      ruleset = FactoryBot.create(:repository_ruleset, :targets_default_branch, source: repo)
      FactoryBot.create(:repository_rule_configuration, repository_ruleset: ruleset, rule_type: "update", parameters: {
        update_allows_fetch_and_merge: false
      })

      ref = repo.heads.create("test", repo.heads["master"].target.first_parent_oid, actor)
      commit = ref.append_commit({ message: "commit", committer: actor }, actor) do |files|
        files.add "file-a", "some content"
      end
      ref_update = create_branch_update(repo, name: "master", before_oid: repo.heads["master"].target_oid, after_oid: commit.oid)

      [ruleset, ref_update]
    end

    sig do
      params(actor: User, file: String, contents: String)
      .returns({
        message: T.nilable(String),
        author_email: T.nilable(String),
        committer_email: T.nilable(String),
        blobs: T::Hash[String, T.nilable(String)]
      })
    end
    def simple_push_metadata(actor, file, contents)
      {
        message: "Create a file",
        author_email: actor.email,
        committer_email: actor.email,
        blobs: {
          file => contents
        },
      }
    end
  end
end
