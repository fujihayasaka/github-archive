require "rails_helper"

module Ingest
  describe RepositoryArchivedProcessor do
    let(:processor) { described_class.new }

    def process
      run_consumer(processor)
    end

    it "deletes repositories from the database" do
      repository = Repository.create(github_repository_id: 1234)

      processor.publish({
        is_archived: true,
        repository_id: repository.github_repository_id,
      })

      # Expect that we'll have one less repository than before.
      expect { process }.to change { Repository.count }.by(-1)
      expect(Repository.find_by_github_repository_id(repository.github_repository_id)).to be_nil
    end
  end
end
