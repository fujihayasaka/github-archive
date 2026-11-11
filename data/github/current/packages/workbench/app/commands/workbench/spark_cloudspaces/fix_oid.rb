# typed: true
# frozen_string_literal: true

module Workbench
  module SparkCloudspaces
    class FixOid
      sig do
        params(codespace: T.nilable(Codespace)).void
      end
      def self.fix_oid(codespace)
        return unless codespace

        repo = T.must(codespace.repository)
        metadata = Repositories.domain.contents.metadata_by_ref_and_path(repository: repo)

        GitHub.dogstats.increment("spark.workbench.fix_user_repo_oid")
        GitHub.logger.info("Applying OID fix to Spark Codespace", {
          guid: codespace.guid,
          repository_id: repo.id,
          old_oid: codespace.oid,
          new_oid: metadata.head_oid,
          devcontainer_path: codespace.devcontainer_path,
        })
        codespace.update!(oid: metadata.head_oid, devcontainer_path: nil)
      end
    end
  end
end
