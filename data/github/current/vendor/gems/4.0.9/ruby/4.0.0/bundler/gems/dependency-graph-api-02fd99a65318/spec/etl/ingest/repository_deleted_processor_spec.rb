require "rails_helper"

module Ingest
  describe RepositoryDeletedProcessor do
    let(:processor) { described_class.new }

    def process
      run_consumer(processor)
    end

    it "deletes repositories from the database" do
      repository = Repository.create(github_repository_id: 1234)

      processor.publish({ repository_id: repository.github_repository_id })

      # Expect that we'll have one less repository than before.
      expect { process }.to change { Repository.count }.by(-1)
    end

    it "doesn't delete repositories that aren't there" do
      allow(DependencyGraph.logger).to receive(:info)

      processor.publish({ repository_id: 8675309 })

      expect { process }.to change { Repository.count }.by(0)

      expect(DependencyGraph.logger).to have_received(:info).with(hash_including({
        fn: :repository_deleted_processor,
        github_repository_id: 8675309,
      })).once
    end
  end
end
