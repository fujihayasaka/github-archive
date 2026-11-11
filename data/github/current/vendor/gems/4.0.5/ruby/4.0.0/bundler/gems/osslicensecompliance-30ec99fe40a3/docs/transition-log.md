# Transition log

Each transition run requires a PR. This is a doc which is updated for each transition with a simple bullet about what is going to be run and why. After PR review and approval, the transition can be executed.

## Logs

- 2025-10-10 @dangoor Fill in values for enterprise_id in olc_alerts and olc_checkjobs and spdx_license_expression in olc_alerts because of column renaming.

- 2025-12-10 @ljones140 Update olc_alerts resolution if `policy_changed` to
  `licenses_added`. Because we want to capture licenses added resolution to go
  with the `exception_added` for package exceptions. 87 rows need to be
  updated.
