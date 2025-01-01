# typed: false
# frozen_string_literal: true

module Repository::EditorConfigDependency
  def load_editor_config(commit, paths, timeout = 1.0)
    self.rpc.fetch_editor_config(commit.tree_oid, Array(paths), timeout: timeout)
  rescue => e # rubocop:todo Lint/GenericRescue
    Failbot.report(e)
    {}
  end
end
