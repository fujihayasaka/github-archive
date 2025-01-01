# typed: false # rubocop:disable Sorbet/TrueSigil
# frozen_string_literal: true

namespace :enterprise do
  namespace :merge_commit_update_refs do
    # Create the Merge Commit Update Refs internal app on a GHES instance.
    task :create => :environment do
      return unless GitHub.enterprise?

      Apps::Privileged::MergeCommitUpdateRefs.seed_database!
    end
  end
end
