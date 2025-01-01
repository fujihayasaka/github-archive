# typed: strict
# frozen_string_literal: true

module RulesEngine
  module RefUpdateTestHelper
    extend T::Sig

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
