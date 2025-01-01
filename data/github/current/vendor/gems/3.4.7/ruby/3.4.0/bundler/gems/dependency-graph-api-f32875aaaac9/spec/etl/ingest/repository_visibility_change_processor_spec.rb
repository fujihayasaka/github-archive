require "rails_helper"

module Ingest
  describe RepositoryVisibilityChangeProcessor do
    let(:processor) { described_class.new }

    def process
      run_consumer(processor)
    end

    before do
      processor.spec_reset

      @public_repository = Repository.create(github_repository_id: 100, github_owner_id: 10, public: true)
      @private_repository = Repository.create(github_repository_id: 200, github_owner_id: 10, public: false)
    end

    it "changes repo visibilites" do
      public_repo_to_private = {
        repository_id: @public_repository.github_repository_id,
        new_visibility: :PRIVATE,
      }

      private_repo_to_public = {
        repository_id: @private_repository.github_repository_id,
        new_visibility: :PUBLIC,
      }

      processor.publish(public_repo_to_private)
      processor.publish(private_repo_to_public)

      process

      public_repo_is_public = Repository.find_by(github_repository_id: @public_repository.github_repository_id).public
      private_repo_is_public = Repository.find_by(github_repository_id: @private_repository.github_repository_id).public

      expect(public_repo_is_public).to be_falsey
      expect(private_repo_is_public).to be_truthy
    end

    it "doesn't change repo visibility if message value matches db value" do
      private_repo_stays_private = {
        repository_id: @private_repository.github_repository_id,
        new_visibility: :PRIVATE,
      }

      processor.publish(private_repo_stays_private)

      process

      private_repo_is_public = Repository.find_by(github_repository_id: @private_repository.github_repository_id).public

      expect(private_repo_is_public).to be_falsey
    end
  end
end
