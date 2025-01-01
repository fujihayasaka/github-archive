export const sshPushProtocol = {
  isAvailable: true,
  isDefault: true,
  stickyUrl: '/users/set_protocol?protocol_selector=ssh&protocol_type=push',
  url: 'ssh://git@localhost:3035/wiseguy/source.git',
  protocol: 'SSH',
}

export const httpPushProtocol = {
  isAvailable: true,
  isDefault: true,
  stickyUrl: '/users/set_protocol?protocol_selector=http&protocol_type=push',
  url: 'http://github.localhost/wiseguy/source.git',
  protocol: 'HTTP',
}

export const defaultMergeInstructionsApiResponse = {
  crossRepoPatchUrl: 'https://github.com/wiseguy/source/pull/1.patch',
  patchUrl: 'https://github.com/wiseguy/source/pull/1.patch',
  resolvingMergeConflictsDocsUrl:
    'https://docs.github.com/pull-requests/collaborating-with-pull-requests/addressing-merge-conflicts/resolving-a-merge-conflict-using-the-command-line',
  shellEscapingDocsUrl:
    'https://docs.github.com/get-started/using-git/dealing-with-special-characters-in-branch-and-tag-names',
  shellSafeCrossRepoHeadRefName: 'sweetsue-topic',
  shellSafeHeadRefName: 'topic',
  shellSafeNamesIncludePlaceholders: false,
  shellSafeBaseRefName: 'master',
  pushProtocols: [sshPushProtocol, httpPushProtocol],
}
