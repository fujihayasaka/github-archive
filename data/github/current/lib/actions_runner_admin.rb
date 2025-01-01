# typed: true
# frozen_string_literal: true
# We used `ActionsRunnerAdmin` instead of `Actions::RunnerAdmin` to avoid interfering with the `Actions` module used by the packwerk package: https://github.com/github/github/tree/master/packages/actions
module ActionsRunnerAdmin
  autoload :Twirp, "actions_runner_admin/twirp"
end
